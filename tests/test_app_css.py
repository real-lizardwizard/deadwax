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

And for Get and the Sources sheet (2.0.0-player.15):

- The Sources sheet has its own scroll lock, sits over Now Playing and under its menu and Info,
  starts where its board does (or under the status bar), is placed clear of a notch rather than
  padded by it, and its list is the one part that scrolls - saying so itself.
- Every control is a tap target to a finger, drawn at the board's size: Get the album, Cancel, the
  chips (30px, reaching 44 - their stacked rows' reaches never overlapping), a card's Get and a
  Search row's Get chip (32px, reaching 44), none with an overflow that would clip its reach.
- The text fields - the query to edit, the sort's own picker - are never small enough for iOS to zoom.
- A source card as its board draws it: the best match's purple edge, the solid Get on it and tinted
  ones on the rest, the score's green and amber badges, the speed's sunken bar with a green fill for
  a measured speed and grey for the peer's own average, the folder giving way with an ellipsis, the
  facts wrapping rather than running off a narrow phone, and the missing line in amber.
- What is already here of a pressing breaks anywhere: its paths are strangers' folder names.
- After review: the sheet's subtitle - which pressing the sources are for, its distinguishing part
  last - has the head's whole width and wraps, never an ellipsis, while the title stays on one line,
  centred, at 320px; the list takes focus a button that ended its state hands it, with no ring; and
  the asking bar of a sheet closed mid-search stops moving.

And for artists and the two libraries joined (2.0.0-player.17):

- The artist page as its board draws it: a 240px hero in its own colour, the picture under it filling
  it, a scrim over the picture only, the back link and the name over that; every row and the back
  link a tap target.
- An album page's artist line, a link, reaches 44px to a finger; its "In your library" row is ONE line,
  so an "Also" chip landing in it moves nothing below and a long edition gives way with an ellipsis -
  the chip's own reach never clipped.
- The Library's chips are the board's 32px, reaching 44, wrapping with room between rows; its sort's
  picker covers the sort whole, unseen, and is never small enough for iOS to zoom.
- A Done row opens its album from the whole row, and its round play button is a 32px face in a 44px
  target.
- Info's folder is a path, broken anywhere, a folder per line.
- After review: the artist page's scrim keeps white words legible over a white sky - the name 3:1
  (on one line or two), the line under it 4.5:1; the line under Play and the albums' heading hold
  their height from the first frame; a row looking for its album fades as a Get chip does; an
  artist's name that isn't a link isn't drawn in the link's colour, and an album page's artist line
  holds its place before the album answers; Info's folder can be selected; and the order chips the
  Library's chips replaced are gone, rules and tokens.
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
    for lock in ("html.app-menu-open", "html.app-info-open", "html.app-sources-open"):
        assert declarations(APP, lock)["overflow"] == "hidden", lock
    #? the classes the sheets put on <html> are exactly these four (Sources since 2.0.0-player.15)
    ui = Path(__file__).resolve().parent.parent / "ui" / "src"
    sheets = {"player/NowPlaying.tsx": "pl-sheet-open", "app/ActionMenu.tsx": "app-menu-open", "app/InfoSheet.tsx": "app-info-open",
              "app/Sources.tsx": "app-sources-open"}
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

def test_the_record_is_turned_by_the_deck_not_by_an_animation():
    """2.0.0-player.14: momentum, the motor, spin-up and spin-down need the platter turned frame by
    frame (player/deck.ts writes the face's transform, at lib/platter.ts's DEGREES_PER_SECOND), so the
    CSS spin of 2.0.0-player.11 went, its token with it - and nothing in the CSS may turn it too."""
    face = declarations(APP, ".app-tt-face")
    assert "animation" not in face and "transform" not in face
    assert face["will-change"] == "transform"
    assert not re.search(r"app-tt-spin(?![\w-])", APP) and ".is-spinning" not in APP
    assert "--dw-record-turn" not in ALL_TOKENS


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


def test_the_sources_sheet_stacks_starts_and_scrolls_as_a_sheet_should():
    #? over the page and Now Playing (20), under Now Playing's menu and Info (30)
    assert declarations(APP, ".app-sources-layer")["z-index"] == "var(--app-z-sources)"
    assert int(declarations(PLAYER_CSS, ".pl-sheet")["z-index"]) < int(ALL_TOKENS["--app-z-sources"]) < int(ALL_TOKENS["--app-z-over"])
    sheet = declarations(APP, ".app-sources")
    assert sheet["top"] == "max(var(--app-sources-top), calc(var(--pl-safe-top) + var(--app-info-pad)))"
    assert ALL_TOKENS["--app-sources-top"] == "48px"  # from the top of the screen, as Sources.dc.html draws it
    #? clear of a notch by where it is placed, never padded by it - as the menu and Info
    assert (sheet["left"], sheet["right"]) == ("var(--pl-safe-left)", "var(--pl-safe-right)")
    assert sheet["max-width"] == "var(--pl-content-max)" and sheet["margin"] == "0 auto"
    assert sheet["padding"] == "var(--app-info-pad) var(--dw-gutter-grouped) 0"
    assert declarations(APP, ".app-layer.is-open .app-sources")["transform"] == "translateY(0)"
    #? its list is the one part that scrolls: the layer takes every touch, a scroller starts its own count
    scroller = declarations(APP, ".app-sources-scroll")
    assert scroller["touch-action"] == "pan-y"
    assert (scroller["overflow-y"], scroller["overflow-x"], scroller["overscroll-behavior"], scroller["min-height"]) == ("auto", "hidden", "contain", "0")
    #? the head and the chips hold still above it
    assert declarations(APP, ".app-sources-head")["flex"] == declarations(APP, ".app-sources-chips")["flex"] == "none"


def test_every_control_of_get_and_the_sources_is_a_tap_target():
    hit = px("--pl-hit")
    hairline = px("--dw-hairline")
    assert declarations(APP, ".app-rg-get")["min-height"] == "var(--pl-hit)"
    assert declarations(APP, ".app-sources-cancel")["min-height"] == "var(--dw-row)" and px("--dw-row") >= hit
    #? drawn at the board's size, reaching 44 above and below from the padding box (inside the border),
    #? with no overflow of their own to clip that reach
    for control, size, reach in ((".app-chip", "--app-chip", "--app-chip-reach"), (".app-source-get", "--app-source-get", "--app-source-get-reach"),
                                 (".app-result-get", "--app-result-get", "--app-result-get-reach")):
        found = declarations(APP, control)
        assert found["height"] == f"var({size})" and found["position"] == "relative", control
        assert found["border"].startswith("var(--dw-hairline) "), control
        assert "overflow" not in found, control
        before = declarations(APP, f"{control}::before")
        assert before["top"] == before["bottom"] == f"calc(-1 * var({reach}))", control
        assert ALL_TOKENS[reach] == f"calc((var(--pl-hit) - var({size})) / 2 + var(--dw-hairline))", control
        assert px(size) - 2 * hairline + 2 * ((hit - px(size)) / 2 + hairline) >= hit, control
    assert (px("--app-chip"), px("--app-source-get"), px("--app-result-get")) == (30, 32, 32)  # as the boards draw them
    #? the chips wrap on a narrow phone: a row's reaches never overlap the next row's, and the row keeps
    #? room above and below for its own
    chips = declarations(APP, ".app-sources-chips")
    assert chips["flex-wrap"] == "wrap" and chips["gap"] == "calc(2 * var(--app-chip-reach)) var(--app-chip-gap)"
    assert chips["padding"] == "var(--app-chip-reach) 0" and chips["margin"] == "calc(-1 * var(--app-chip-reach)) 0"


def test_the_sources_text_fields_are_never_small_enough_for_ios_to_zoom():
    for field in (".app-sources-query-input", ".app-sources-sort-select"):
        assert declarations(APP, field)["font-size"] == "var(--dw-text-body)", field
    assert px("--dw-text-body") >= 16
    #? the sort's own picker covers its chip whole, unseen - the chip shows what it says
    select = declarations(APP, ".app-sources-sort-select")
    assert (select["position"], select["inset"], select["opacity"]) == ("absolute", "0", "var(--app-chip-select)")
    assert ALL_TOKENS["--app-chip-select"] == "0"


def test_a_source_card_is_drawn_as_its_board_has_it():
    assert declarations(APP, ".app-source.is-best")["border-color"] == "var(--dw-best)"
    assert ALL_TOKENS["--dw-best"] == "#7e4bb8"  # STYLE.md's "selected / best match"
    #? the solid purple on the best match's Get, the toggled tint on the rest
    assert declarations(APP, ".app-source-get.is-primary")["background"] == "var(--dw-primary-bg)"
    assert declarations(APP, ".app-source-get.is-tinted")["background"] == "var(--dw-toggled-bg)"
    assert declarations(APP, ".app-rg-get")["background"] == "var(--dw-primary-bg)"
    #? the score: green from the good band up, amber under it
    assert declarations(APP, ".app-source-score")["color"] == "var(--dw-amber-text)"
    assert declarations(APP, ".app-source-score.is-good")["color"] == "var(--dw-badge-green-text)"
    #? the speed's bar is STYLE.md's sunken track: green for a speed deadwax measured, grey for the
    #? peer's own average, nothing for none
    bar = declarations(APP, ".app-source-bar")
    assert (bar["height"], bar["background"], bar["box-shadow"], bar["overflow"]) == ("var(--app-source-bar)", "var(--dw-track)", "var(--dw-track-inset)", "hidden")
    assert px("--app-source-bar") == 8
    assert declarations(APP, ".app-source-bar-fill")["background"] == "var(--dw-bar-grey)"
    assert declarations(APP, ".app-source-bar-fill.is-measured")["background"] == "var(--dw-bar-green)"
    assert ALL_TOKENS["--dw-bar-green"] == "linear-gradient(to bottom, #5ee39a, #34c47f)"
    assert declarations(APP, ".app-source-speed-text.is-measured")["color"] == "var(--dw-badge-green-text)"
    #? the folder gives way; the facts and the speed line wrap rather than run off a narrow phone
    assert declarations(APP, ".app-source-name")["min-width"] == "0"
    folder = declarations(APP, ".app-source-folder")
    assert (folder["overflow"], folder["text-overflow"], folder["white-space"]) == ("hidden", "ellipsis", "nowrap")
    assert declarations(APP, ".app-source-facts")["flex-wrap"] == declarations(APP, ".app-source-speed-line")["flex-wrap"] == "wrap"
    missing = declarations(APP, ".app-source-missing")
    assert missing["color"] == "var(--dw-amber-text)" and missing["overflow-wrap"] == "anywhere"


def test_the_sources_subtitle_has_the_whole_width_and_wraps():
    #? Cancel and an empty column either side of the title share what it leaves, so it stays centred
    #? and on one line; the subtitle spans all three, under them, and wraps
    head = declarations(APP, ".app-sources-head")
    assert (head["display"], head["grid-template-columns"]) == ("grid", "1fr auto 1fr")
    title = declarations(APP, ".app-sources-title")
    assert (title["grid-column"], title["white-space"], title["text-align"]) == ("2", "nowrap", "center")
    subtitle = declarations(APP, ".app-sources-subtitle")
    assert (subtitle["grid-column"], subtitle["grid-row"], subtitle["overflow-wrap"]) == ("1 / -1", "2", "anywhere")
    assert "white-space" not in subtitle and "text-overflow" not in subtitle and "overflow" not in subtitle
    assert declarations(APP, ".app-sources-cancel")["grid-column"] == "1"
    #? the old fixed 80px side columns, which left the title 128px at 320, are gone
    assert "--app-sources-side" not in ALL_TOKENS


def test_the_sources_list_takes_focus_without_a_ring_and_a_closed_sheets_bar_stops():
    assert declarations(APP, ".app-sources-scroll:focus") == {"outline": "none"}
    assert declarations(APP, ".app-sources-layer:not(.is-open) .app-sweep::before") == {"animation-play-state": "paused"}


def test_what_is_already_here_of_a_pressing_breaks_anywhere():
    for selector in (".app-store-line", ".app-store-note", ".app-sources-state-text", ".app-sources-footer"):
        assert declarations(APP, selector)["overflow-wrap"] == "anywhere", selector
    #? nothing there to say takes no room under Get - and is still drawn, a live region VoiceOver
    #? already knows of (it reads one only once it is there; a hidden one isn't)
    assert declarations(APP, ".app-rg-store:empty") == {"margin-top": "calc(-1 * var(--app-rg-get-gap))"}
    assert declarations(APP, ".app-rg-actions")["gap"] == "var(--app-rg-get-gap)"



# ---------------------------------------------------------------- artists and the id bridge (2.0.0-player.17)

def test_the_artist_page_is_drawn_as_its_board_has_it():
    hero = declarations(APP, ".app-artist-hero")
    assert (hero["min-height"], hero["background"], hero["position"], hero["overflow"]) == (
        "var(--app-artist-hero)", "var(--dw-artist-hero)", "relative", "hidden")
    assert px("--app-artist-hero") == 240 and ALL_TOKENS["--dw-artist-hero"] == "#3a2530"
    #? clear of the status bar and placed by the insets, never padded by both
    assert hero["padding"].startswith("calc(var(--pl-safe-top) + var(--app-artist-hero-pad)) var(--pl-edge-right)")
    picture = declarations(APP, ".app-artist-picture")
    assert (picture["position"], picture["inset"], picture["object-fit"]) == ("absolute", "0", "cover")
    #? the scrim only over a picture: a hero in its own colour stays that colour
    scrim = declarations(APP, ".app-artist-hero:has(img.app-artist-picture)::after")
    assert scrim["background"] == "var(--dw-artist-scrim)" and scrim["position"] == "absolute"
    assert declarations(APP, ".app-artist-picture.is-empty") == {"display": "none"}
    assert declarations(APP, ".app-artist-names")["z-index"] == "var(--app-z-hero-words)"
    #? the back link and every row a tap target; a row's words give way
    assert declarations(APP, ".app-artist-back")["min-height"] == "var(--pl-hit)"
    assert declarations(APP, ".app-artist-album")["min-height"] == "var(--app-artist-row)" and px("--app-artist-row") >= px("--pl-hit")
    assert declarations(APP, ".app-artist-album")["min-width"] == "0"
    words = declarations(APP, ".app-artist-line-text")
    assert (words["overflow"], words["text-overflow"], words["white-space"], words["min-width"]) == ("hidden", "ellipsis", "nowrap", "0")


def test_an_album_pages_artist_link_and_also_chips():
    link = declarations(APP, ".app-hero-link::before")
    assert link["top"] == link["bottom"] == "calc(-1 * var(--app-hero-link-reach))"
    assert ALL_TOKENS["--app-hero-link-reach"] == "calc((var(--pl-hit) - 1.25em) / 2)"
    #? one line, from the first frame: no wrap, so a chip landing never pushes Play down a row
    chips = declarations(APP, ".app-album-chips")
    assert chips["display"] == "flex" and "flex-wrap" not in chips
    assert declarations(APP, ".app-album-chips > *")["min-width"] == "0"
    label = declarations(APP, ".app-also-label")
    assert (label["overflow"], label["text-overflow"], label["white-space"]) == ("hidden", "ellipsis", "nowrap")
    #? the chip itself keeps no overflow, so its 44px reach isn't clipped (it is an .app-chip)
    assert "overflow" not in declarations(APP, ".app-also")
    badge = declarations(APP, ".app-held-badge")
    assert (badge["flex"], badge["height"], badge["color"], badge["background"]) == (
        "none", "var(--app-chip)", "var(--dw-badge-green-text)", "var(--dw-badge-green-bg)")


def test_the_librarys_chips_and_sort():
    hit, hairline = px("--pl-hit"), px("--dw-hairline")
    assert px("--app-library-view") == 32  # as the board draws them
    assert declarations(APP, ".app-chip.app-library-view")["height"] == "var(--app-library-view)"
    before = declarations(APP, ".app-chip.app-library-view::before")
    assert before["top"] == before["bottom"] == "calc(-1 * var(--app-library-view-reach))"
    assert ALL_TOKENS["--app-library-view-reach"] == "calc((var(--pl-hit) - var(--app-library-view)) / 2 + var(--dw-hairline))"
    assert px("--app-library-view") - 2 * hairline + 2 * ((hit - px("--app-library-view")) / 2 + hairline) >= hit
    views = declarations(APP, ".app-library-views")
    assert views["flex-wrap"] == "wrap" and views["gap"] == "calc(2 * var(--app-library-view-reach)) var(--app-library-gap)"
    assert declarations(APP, ".app-sort")["min-height"] == "var(--pl-hit)"
    select = declarations(APP, ".app-sort-select")
    assert (select["position"], select["inset"], select["opacity"], select["font-size"]) == (
        "absolute", "0", "var(--app-chip-select)", "var(--dw-text-body)")
    assert px("--dw-text-body") >= 16


def test_a_done_row_opens_from_the_whole_row_and_plays_from_its_round_button():
    assert declarations(APP, ".app-done-open")["min-height"] == "var(--app-done-row)"
    assert declarations(APP, ".app-done-open")["flex"] == "1"
    play = declarations(APP, ".app-done-play")
    assert (play["width"], play["height"]) == ("var(--pl-hit)", "var(--pl-hit)")
    face = declarations(APP, ".app-done-play-face")
    assert (face["width"], face["border-radius"]) == ("var(--app-done-play-face)", "var(--dw-radius-round)")
    assert px("--app-done-play-face") == 32


def test_infos_folder_is_a_path_a_folder_a_line():
    folder = declarations(APP, ".app-info-folder")
    assert folder["white-space"] == "pre-line"
    assert declarations(APP, ".app-kv-value")["overflow-wrap"] == "anywhere"
    #? the one string on the sheet people copy (review: inside the album's button it couldn't be)
    assert folder["user-select"] == folder["-webkit-user-select"] == "text"


# ---------------------------------------------------------------- after review (2.0.0-player.17)

def _srgb_luminance(value: float) -> float:
    channel = value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
    return channel  # grey: every channel the same


def _contrast_over_white(alpha: float, text: float) -> float:
    """White (or a light grey `text`, 0-1) words over a pure white photo under black at `alpha`."""
    under = _srgb_luminance(1 - alpha)
    over = _srgb_luminance(text)
    return (max(under, over) + 0.05) / (min(under, over) + 0.05)


def test_the_artist_heros_scrim_keeps_the_words_legible_over_a_white_sky():
    """Over a white part of a photo: the name 3:1 (large text) on one line or two, the facts 4.5:1.
    Positions from the hero's own tokens - the name and the facts sit at its foot."""
    stops = [(float(pct), float(alpha)) for alpha, pct in
             re.findall(r"rgba\(0, 0, 0, ([\d.]+)\) (\d+)%", ALL_TOKENS["--dw-artist-scrim"])]
    assert stops and stops[0][0] == 0 and stops[-1][0] == 100 and stops[0][1] >= 0.4  # the back link's dark

    def alpha(pct: float) -> float:
        for (p0, a0), (p1, a1) in zip(stops, stops[1:]):
            if p0 <= pct <= p1:
                return a0 + (a1 - a0) * (pct - p0) / (p1 - p0)
        return stops[-1][1]

    hero = px("--app-artist-hero")
    foot = px("--app-artist-hero-foot")
    facts = px("--dw-text-footnote") * float(ALL_TOKENS["--dw-leading-note"])
    name = px("--dw-text-large-title") * float(ALL_TOKENS["--dw-leading-title"])
    facts_top = hero - foot - facts
    name_bottom = facts_top - px("--app-line-gap")
    two_lines_top = name_bottom - 2 * name
    light = int(ALL_TOKENS["--dw-text-on-secondary"][1:3], 16) / 255

    def worst(top: float, bottom: float, text: float) -> float:
        return min(_contrast_over_white(alpha(100 * y / hero), text) for y in range(int(top), int(bottom) + 1))

    assert worst(two_lines_top, name_bottom, 1.0) >= 3
    assert worst(facts_top, hero - foot, light) >= 4.5


def test_what_lands_late_on_the_artist_page_moves_nothing():
    #? the line under Play and Shuffle holds a line whatever it says, or doesn't
    assert declarations(APP, ".app-artist-plays")["min-height"] == "var(--app-artist-plays-line)"
    assert ALL_TOKENS["--app-artist-plays-line"] == "calc(var(--dw-text-footnote) * var(--dw-leading-note))"
    #? "Albums" as tall as the Studio only chip that comes once the artist's id is known
    assert declarations(APP, ".app-artist-albums-head")["min-height"] == "var(--app-chip)"
    #? an album page's artist line holds its line before the album answers
    assert declarations(APP, ".app-shell .pl-hero-artist")["min-height"] == "var(--app-hero-artist-line)"
    assert ALL_TOKENS["--app-hero-artist-line"] == "1.25em"
    assert declarations(PLAYER_CSS, ".pl-hero-artist")["line-height"] == "1.25"


def test_a_row_looking_for_its_album_fades_and_a_name_that_isnt_a_link_isnt_the_links_colour():
    for row in (".app-artist-album.is-busy", ".app-result.is-busy", ".app-done-open.is-busy"):
        assert declarations(APP, row) == {"opacity": "var(--app-job-busy)"}, row
    assert declarations(APP, ".app-hero-plain") == {"color": "var(--dw-text-2)"}
    assert declarations(PLAYER_CSS, ".pl-hero-artist")["color"] == "var(--pl-accent)"


def test_the_order_chips_the_librarys_chips_replaced_are_gone():
    selectors = {selector.strip() for _, found, _ in rules(PLAYER_CSS) for selector in found.split(",")}
    assert not [selector for selector in selectors if re.search(r"\.pl-orders?\b", selector)]
    assert not [token for token in ("--pl-chip-pad", "--pl-toggled-bg", "--pl-toggled-edge") if token in ALL_TOKENS]
