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

And for pins and a finished Home (2.0.0-player.18):

- The pin on an album page and an artist page as their boards draw it - a 32px box, an icon button
  or a chip, toggled purple once pinned with its head filled, faded while it can't be used - reaching
  44px to a finger every way, with nothing clipping the reach; the album page's bar and the artist
  hero's top row hold the back link at their left and the pin at their right, a gap between, the back
  link giving way (min-width 0) whatever the page below is called - an album's long title pushed the
  artist's pin out of the hero, where it was clipped.
- Home's Pinned as its board draws it: two columns of 64px cards, a 48px picture, an artist's round,
  a name of two lines at most over a sub-line that gives way with an ellipsis; a card that won't open
  steps back its picture and says why in two lines (its title one) in the sub-line's own colour, and
  under 374px the cards take one column, so those words are read whole. Edit, a tap target square at
  least; "Not saved" under the list, taking room only while it says something.
- Edit's up, down and unpin are 32px faces in 44px boxes side by side, no gap between - 44 to a finger
  every way; the grip is a tap target square, the one part of a row that takes a drag (touch-action:
  none) - the rest of the row lets the page scroll; the row being dragged sits over the rest.
- The app's one notice for pins: fixed at the top, over Now Playing's menu and Info, taking no taps,
  clipped away (never removed) while it says nothing.

And for inside a track, the cover viewer and an album's Properties (2.0.0-player.44), on both frames:

- The cover viewer covers the whole window over everything but the pin notice, inside the screen's safe
  areas, takes every touch (its own pinch and drag), has a scroll lock of its own, and tells a hand that
  taps and pinches so; its ✕ and Close are tap targets, their rings drawn inside the frame.
- An album page's cover is a button with the hero cover's own class, the picture filling it.
- The track inspector fits a 390px panel: every field a row of a label column and a value that breaks
  anywhere (ids, paths, strangers' tags), the value column never squeezed under 200px there; its buttons,
  pictures and "All tags in this file" a tap target each, and - running to the panel body's clipping
  edges - their rings drawn inside, as Artwork's cover's and CD art's are; a track's name in the Tags
  list a button of its own.
- Properties: the labels a column, a release id broken anywhere, its link a finger's height without
  moving its line - worked out from the list's own type tokens, all of it hit (positioned over the rows
  either side).

And for the artist page as the main page had it (2.0.0-player.45):

- Its panel on a phone: a sheet over the whole screen - from the very top, its words clear of the status
  bar by its padding, placed clear of a notch rather than padded by it, its foot over the home
  indicator - with a scroll lock of its own and a body that is the one part that scrolls (saying so: the
  layer takes every touch); its asking bar stops moving as it closes; its close button, its buttons, the
  checkbox's label and its inline buttons a finger's target; its search box never small enough for iOS
  to zoom into; a path broken anywhere; Save's line held at its height; a body with no foot under it
  clear of the home indicator by its own padding; on a phone on its side the sheet scrolling as one; and
  each picture to choose in a box of its slot's shape, the picture fitted inside, so one loading late
  moves nothing beside it.
- On the page: their logo in their name's place, never wider than the hero; Artist images…, Move albums
  to … and Which artist is this? the secondary button a finger tall, toggled while the panel shows them
  and stepped back (still in reach) while they can't be used; the folder a path, a folder per line,
  broken anywhere; a link and a fold a finger's target; a past member stepped back by a token.

And for the speed fader (2.0.0-player.39):

- The fader takes every touch on it (touch-action: none), a tap target wide - a share of the plinth on
  a small one, the arm handle's rule - and never on the record (from just past its rim where centring on
  the slot would reach it); its readout a tap target the same way, its words a label's size and smaller
  with the plinth, its well opaque and drawn over a failure line laid across the plinth's foot; the
  knob, the slot and the mark drawn from the theme's tokens.
- The chip: a tap target tall, STYLE.md's toggled chip inside it, at the start of the icon row that is
  one fixed height - so it moves nothing coming and going - and on the turntable only on a phone on its
  side, where the plinth is too small to read the readout.

And for looking after deadwax from a phone (2.0.0-player.47) - every rule of its section under the phone's
frame (`.app-shell:not(.app-desk)`), so the desktop is drawn by app-desktop.css alone, as before:

- The Edit panel a sheet over the whole screen, as the artist page's: from the very top, clear of the status
  bar by padding and of a notch by where it is placed, a scroll lock of its own, no transform once open (the
  cover viewers inside it are the screen's), its body the one part that scrolls; on a phone on its side its
  title beside its tabs. The hosted editors' fields 17px and a finger tall, every target 44px, the preview's
  changes a tag over old and new, long names broken anywhere, Apply sticky at the foot above the home
  indicator; the album page's Edit a chip in the bar, the pin's size, its reach a finger's.
- Needs a look's rows, Library care, the settings (a key over its field, the save bar above the tab bar and
  the mini player, taking no taps until it says something, the scroll padding clear of it - on one line
  where the window is wide enough) and the log (a line's time, level and source over its words, which wrap).
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


def length(token: str) -> float:
    """A token that is a px length - plain, or a calc() of px tokens and plain numbers - as a number."""
    value = ALL_TOKENS[token]
    expression = re.sub(r"var\((--[\w-]+)\)", lambda found: f"({length(found.group(1))})", value)
    expression = expression.replace("calc", "").replace("px", "")
    #? nothing but arithmetic is ever evaluated
    assert re.fullmatch(r"[\d\s.+\-*/()]+", expression), (token, value)
    return float(eval(expression))


def test_each_sheet_has_its_own_scroll_lock():
    assert declarations(PLAYER_CSS, "html.pl-sheet-open")["overflow"] == "hidden"
    for lock in ("html.app-menu-open", "html.app-info-open", "html.app-sources-open", "html.app-viz-open"):
        assert declarations(APP, lock)["overflow"] == "hidden", lock
    #? the classes the sheets put on <html> are exactly these four (Sources since 2.0.0-player.15)
    ui = Path(__file__).resolve().parent.parent / "ui" / "src"
    sheets = {"player/NowPlaying.tsx": "pl-sheet-open", "app/ActionMenu.tsx": "app-menu-open", "app/InfoSheet.tsx": "app-info-open",
              "app/Sources.tsx": "app-sources-open"}
    for file, lock in sheets.items():
        assert f"lockClass: '{lock}'" in (ui / file).read_text(), file
    #? the desktop's visualizer (2.0.0-player.20) isn't a sheet, and puts its own on as it shows
    visualizer = (ui / "player" / "Visualizer.tsx").read_text()
    assert "export const SCROLL_LOCK = 'app-viz-open'" in visualizer
    assert re.search(r"page\.classList\.add\(SCROLL_LOCK\)\s*return \(\) => page\.classList\.remove\(SCROLL_LOCK\)", visualizer)


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


def test_the_pin_is_drawn_as_its_boards_draw_it_and_reaches_44px():
    pin = declarations(APP, ".app-pin-toggle")
    assert pin["height"] == "var(--app-pin-toggle)" and "overflow" not in pin
    assert px("--app-pin-toggle") == 32
    assert declarations(APP, ".app-pin-toggle.is-icon")["width"] == "var(--app-pin-toggle)"
    assert declarations(APP, ".app-pin-toggle::before")["inset"] == "calc(-1 * var(--app-pin-toggle-reach))"
    #? the reach starts at the padding box, inside the border: 32 + 2 x (6 + 1) = 46, at least 44
    assert ALL_TOKENS["--app-pin-toggle-reach"] == "calc((var(--pl-hit) - var(--app-pin-toggle)) / 2 + var(--dw-hairline))"
    on = declarations(APP, ".app-pin-toggle.is-on")
    assert (on["background"], on["border-color"], on["color"]) == ("var(--dw-toggled-bg)", "var(--dw-toggled-border)", "var(--dw-accent-text)")
    assert declarations(APP, ".app-pin-toggle.is-on .app-pin-head") == {"fill": "currentColor"}
    assert declarations(APP, ".app-pin-toggle[aria-disabled='true']") == {"opacity": "var(--app-pin-off)"}
    bar = declarations(APP, ".app-album-bar")
    assert (bar["display"], bar["justify-content"]) == ("flex", "space-between")
    assert declarations(APP, ".app-album-bar .pl-back")["min-width"] == "0"


def test_the_artist_heros_back_link_gives_way_to_the_pin():
    """Its label is the page below's - an album's title, as often as not: without min-width 0 the link
    kept its whole label's width and pushed the pin out of the hero, whose overflow clipped it."""
    top = declarations(APP, ".app-artist-top")
    assert (top["display"], top["justify-content"], top["gap"]) == ("flex", "space-between", "var(--pl-gap-sm)")
    back = declarations(APP, ".app-artist-back")
    assert (back["min-width"], back["max-width"]) == ("0", "100%")
    assert declarations(APP, ".app-artist-hero")["overflow"] == "hidden"
    assert declarations(APP, ".app-pin-toggle")["flex"] == "none"


def test_home_pins_two_columns_of_cards_as_the_board_has_them():
    grid = declarations(APP, ".app-pins")
    assert grid["grid-template-columns"] == "repeat(2, minmax(0, 1fr))"
    assert grid["gap"] == "var(--app-pins-gap)" and px("--app-pins-gap") == 10
    card = declarations(APP, ".app-pin-card")
    assert (card["height"], card["padding"], card["border-radius"]) == ("var(--app-pin-card)", "var(--app-pin-pad)", "var(--dw-radius-card)")
    assert (px("--app-pin-card"), px("--app-pin-pad"), px("--app-pin-thumb")) == (64, 7, 48)
    assert declarations(APP, ".app-pin-thumb")["border-radius"] == "var(--dw-radius-cover)"
    assert declarations(APP, ".app-pin-thumb.is-round")["border-radius"] == "var(--dw-radius-round)"
    title = declarations(APP, ".app-pin-title")
    assert title["-webkit-line-clamp"] == "var(--app-pin-title-clamp)" and ALL_TOKENS["--app-pin-title-clamp"] == "2"
    line = declarations(APP, ".app-pin-line")
    assert (line["text-overflow"], line["white-space"]) == ("ellipsis", "nowrap")
    assert declarations(APP, ".app-pin-text")["min-width"] == "0"
    assert declarations(APP, ".app-pin-card.is-closed .app-pin-thumb") == {"opacity": "var(--app-pin-off)"}


def test_a_card_that_wont_open_says_why_in_words_read_whole():
    """"Removed from the store" is about 137px of 12px Noto Sans, and a phone's card had 96 at 390px,
    61 at 320: the words wrap to two lines, the title gives one up, and under 374px one column."""
    assert declarations(APP, ".is-closed .app-pin-title")["-webkit-line-clamp"] == "var(--app-pin-closed-title-clamp)"
    closed = declarations(APP, ".is-closed .app-pin-line")
    assert (closed["white-space"], closed["display"], closed["-webkit-line-clamp"]) == ("normal", "-webkit-box", "var(--app-pin-closed-line-clamp)")
    assert (ALL_TOKENS["--app-pin-closed-title-clamp"], ALL_TOKENS["--app-pin-closed-line-clamp"]) == ("1", "2")
    #? one title line and two of words fit the card: 17 + 2 x 14 within its 64 - 2 x 7 - 2 x 1
    assert px("--app-pin-title-line") + 2 * px("--app-pin-line-line") <= px("--app-pin-card") - 2 * px("--app-pin-pad") - 2
    #? the words in the sub-line's own colour - the only place a closed card says why
    assert "color" not in closed and not [selector for _, selector, values in rules(APP) if "is-closed" in selector and "color" in values]
    assert declarations(APP, ".app-pins", "@media (max-width: 373px)")["grid-template-columns"] == "minmax(0, 1fr)"


def test_edit_and_the_note_under_pinned():
    edit = declarations(APP, ".app-pinned-edit")
    assert (edit["min-width"], edit["padding"], edit["text-align"]) == ("var(--pl-hit)", "0", "right")
    note = declarations(APP, ".app-pinned-note")
    assert note["margin"] == "0" and declarations(APP, ".app-pinned-note.is-said") == {"margin-top": "var(--app-job-gap)"}


def test_the_pin_notice_is_over_everything_takes_no_taps_and_stays_in_the_page():
    notice = declarations(APP, ".app-pin-notice")
    assert (notice["position"], notice["pointer-events"], notice["z-index"]) == ("fixed", "none", "var(--app-z-notice)")
    assert int(ALL_TOKENS["--app-z-notice"]) > int(ALL_TOKENS["--app-z-over"])
    assert notice["top"] == "calc(var(--pl-safe-top) + var(--app-pin-notice-top))"
    #? clipped, never display: none or visibility: hidden - either takes a live region out of what iOS reads
    assert declarations(APP, ".app-pin-notice:not(.is-shown)") == {"clip-path": "inset(50%)"}


def test_edits_buttons_reach_44px_and_only_the_grip_takes_a_drag():
    """Each a 32px face in a 44px box, side by side with no gap: 32px wide boxes 4px apart put unpin a
    few pixels from a thumb aimed at down."""
    move = declarations(APP, ".app-pin-move")
    assert (move["width"], move["height"]) == ("var(--pl-hit)", "var(--pl-hit)")
    face = declarations(APP, ".app-pin-move-face")
    assert (face["width"], face["height"]) == ("var(--app-pin-move-face)", "var(--app-pin-move-face)") and px("--app-pin-move-face") == 32
    assert "gap" not in declarations(APP, ".app-pin-row")
    assert not declarations(APP, ".app-pin-move::before")
    grip = declarations(APP, ".app-pin-grip")
    assert (grip["width"], grip["height"], grip["touch-action"]) == ("var(--pl-hit)", "var(--pl-hit)", "none")
    #? nothing else in a row says touch-action, so the page scrolls under a finger anywhere but the grip
    assert not [selector for _, selector, values in rules(APP) if "app-pin" in selector and "touch-action" in values and selector != ".app-pin-grip"]
    assert declarations(APP, ".app-pin-row.is-dragging")["z-index"] == "var(--app-z-pin-drag)"
    assert declarations(APP, ".app-pin-row .app-pin-text")["flex"] == "1"


# ------------------------------------------------------------------- the speed fader (2.0.0-player.39)

def test_the_fader_takes_every_touch_and_is_a_tap_target_unless_the_plinth_is_small():
    fader = declarations(APP, ".app-tt-fader")
    assert (fader["touch-action"], fader["user-select"], fader["-webkit-touch-callout"]) == ("none", "none", "none")
    assert fader["position"] == "absolute" and "transform" not in fader
    #? 44px, but never more than a share of the plinth: on a phone on its side (a 45px plinth) a 44px
    #? fader beside the record would cover it - the arm handle's rule
    assert fader["width"] == "min(var(--pl-hit), var(--app-tt-fader-cap))"
    #? centred on the slot only while that keeps it off the record: else from just past the record's rim
    #? (review of 2.0.0-player.39 - centred, it covered the rim on every phone, and took its taps and
    #? turns). The two places come inline from lib/playSpeed; playspeed.sim holds faderTarget to this
    assert fader["left"] == "max(var(--app-tt-fader-from), calc(var(--app-tt-fader-x) - min(var(--pl-hit), var(--app-tt-fader-cap)) / 2))"
    assert ALL_TOKENS["--app-tt-fader-cap"] == "14%"
    readout = declarations(APP, ".app-tt-readout")
    assert readout["min-width"] == readout["min-height"] == "min(var(--pl-hit), var(--app-tt-fader-cap))"
    assert readout["transform"] == "translate(-50%, -50%)"
    face = declarations(APP, ".app-tt-readout-face")
    #? a label's size, and smaller with the plinth - the room's container units - so it never spills
    assert face["font-size"] == "var(--app-tt-readout-text)" and face["font-family"] == "var(--dw-font-mono)" and face["white-space"] == "nowrap"
    #? no var() of the stage's: a custom property's var() is filled in where it is defined - :root - and
    #? one undefined there made the whole token invalid, the words the page's 17px (the real page showed it)
    assert ALL_TOKENS["--app-tt-readout-text"] == "min(var(--dw-text-label), 3.2cqw, 3.2cqh)"
    assert declarations(APP, ".app-tt")["container-type"] == "size"
    #? off 1x, STYLE.md's toggled look; at 1x a well - each tint laid on the plinth's own colour, so the
    #? face is opaque: drawn OVER a failure line laid across the plinth's foot, which reaches it on a phone
    #? short of height (review of 2.0.0-player.39 - red words ran through its purple ones), the same pixels
    #? as before on the plinth
    assert (face["background"], face["box-shadow"]) == ("linear-gradient(var(--dw-well), var(--dw-well)), var(--dw-tt-plinth)", "var(--dw-well-inset)")
    off = declarations(APP, ".app-tt-readout.is-off .app-tt-readout-face")
    assert (off["background"], off["border-color"]) == (
        "linear-gradient(var(--dw-toggled-bg), var(--dw-toggled-bg)), var(--dw-tt-plinth)", "var(--dw-toggled-border)")
    assert readout["z-index"] == "var(--app-z-tt-readout)" and ALL_TOKENS["--app-z-tt-readout"] == "1"
    #? the failure line it is drawn over: no z-index of its own, nor anything between the readout and the
    #? sheet that would make a stacking context and keep the readout's under it
    assert "z-index" not in declarations(APP, ".app-is-turntable .pl-sheet-error")
    for between in (".app-tt-stage", ".app-tt"):
        rule = declarations(APP, between)
        assert not ({"z-index", "isolation", "transform", "filter", "opacity", "contain", "will-change"} & set(rule)), between
    #? the drawing: the slot STYLE.md's track, the knob the arm's greys, the mark lit green at 1x
    assert declarations(APP, ".app-tt-fader-slot") == {"fill": "var(--dw-track)", "stroke": "var(--dw-border)"}
    assert declarations(APP, ".app-tt-fader-knob")["fill"] == "var(--dw-tt-arm-weight)"
    assert declarations(APP, ".app-tt-fader-mark.is-on")["fill"] == "var(--dw-green-icon)"


def test_the_speed_chip_moves_nothing_and_shows_on_the_turntable_only_on_a_phone_on_its_side():
    chip = declarations(APP, ".app-speed-chip")
    #? a tap target tall in a row that is one: its height is the row's, and it sits at the row's start
    assert chip["height"] == "var(--pl-hit)" and chip["margin-right"] == "auto" and chip["flex"] == "none"
    assert declarations(PLAYER_CSS, ".pl-sheet-footer")["height"] == "var(--pl-hit)"
    assert declarations(PLAYER_CSS, ".pl-sheet-footer")["justify-content"] == "flex-end"
    face = declarations(APP, ".app-speed-chip-face")
    assert (face["height"], face["background"], face["border"], face["color"]) == (
        "var(--app-speed-chip)", "var(--dw-toggled-bg)", "var(--dw-hairline) solid var(--dw-toggled-border)", "var(--dw-accent-text)")
    assert ALL_TOKENS["--app-speed-chip"] == "28px" and face["border-radius"] == "var(--dw-radius-control)"
    #? on the turntable the readout says it - but on a phone on its side the plinth is too small to read
    assert declarations(APP, ".app-is-turntable .app-speed-chip") == {"display": "none"}
    assert declarations(APP, ".app-is-turntable .app-speed-chip", "@media (max-height: 500px)") == {"display": "grid"}



# ---------------------------------------------------------------- Get, as the main page had it (2.0.0-player.41)

def test_a_sources_reasons_open_from_a_tap_target_on_the_score_and_hide_while_closed():
    hit, hairline = px("--pl-hit"), px("--dw-hairline")
    #? a phone's score is the button: the board's box widened by its chevron, 44px to a finger
    toggle = declarations(APP, ".app-source-score.is-toggle")
    assert (toggle["position"], toggle["min-width"], toggle["width"]) == ("relative", "var(--app-source-score-width)", "auto")
    before = declarations(APP, ".app-source-score.is-toggle::before")
    assert before["top"] == before["bottom"] == "calc(-1 * var(--app-source-score-reach))"
    assert ALL_TOKENS["--app-source-score-reach"] == "calc((var(--pl-hit) - var(--app-source-score-height)) / 2 + var(--dw-hairline))"
    #? ...reaching from the padding box of the box it widens (border-box, a hairline's border): that box's
    #? own height, less its border, and the reach above and below, make a tap target at least
    score = declarations(APP, ".app-source-score")
    assert score["height"] == "var(--app-source-score-height)"
    assert score["border"].startswith("var(--dw-hairline) ")
    assert declarations(PLAYER_CSS, "*")["box-sizing"] == "border-box"
    height = px("--app-source-score-height")
    assert height - 2 * hairline + 2 * length("--app-source-score-reach") >= hit
    assert "overflow" not in declarations(APP, ".app-source-score") and "overflow" not in toggle
    #? the chevron turns as they open
    assert declarations(APP, '.app-source-score[aria-expanded="true"] .app-source-score-icon')["transform"] == "rotate(var(--app-source-score-turn))"
    #? no display of their own, anywhere, so `hidden` hides them on a phone (the gotcha: a display set
    #? in CSS beats the attribute) - their two lines are the flex rows
    desk = (PLAYER / "app-desktop.css").read_text()
    for css in (APP, desk):
        for _context, selector, values in rules(css):
            if selector.endswith(".app-source-reasons"):
                assert "display" not in values, selector
    #? on a desktop's panel, across the card under the facts
    assert declarations(desk, ".app-desk .app-layer.is-panel .app-source-reasons", "@media (min-width: 1024px)") == {"grid-column": "1 / -1"}


def test_a_sources_signals_and_edition_words_are_drawn_in_their_bands_colours():
    #? the signals: amber in the middle band, green from 75, red under 40 - STYLE.md's badges, and a red one
    signal = declarations(APP, ".app-source-signal")
    assert (signal["background"], signal["color"], signal["height"], signal["white-space"]) == (
        "var(--dw-badge-amber-bg)", "var(--dw-amber-text)", "var(--app-source-signal)", "nowrap")
    assert declarations(APP, ".app-source-signal.is-good")["color"] == "var(--dw-badge-green-text)"
    bad = declarations(APP, ".app-source-signal.is-bad")
    assert (bad["background"], bad["border-color"], bad["color"]) == ("var(--dw-badge-red-bg)", "var(--dw-badge-red-border)", "var(--dw-danger-text)")
    assert {"--dw-badge-red-bg", "--dw-badge-red-border"} <= set(tokens(THEME_CSS))
    #? the edition words in the folder's name, in the main page's colours
    for tone, colour in (("amber", "var(--dw-amber-text)"), ("red", "var(--dw-danger-text)"), ("purple", "var(--dw-accent-text)"), ("green", "var(--dw-badge-green-text)")):
        assert declarations(APP, f".app-source-tag.is-{tone}")["color"] == colour, tone
    tag = declarations(APP, ".app-source-tag")
    assert tag["color"] == "var(--dw-text-on-secondary)"
    #? the words clear of the tag's border, as the main page's tag has them (review: the token was never
    #? defined, so the padding fell back to 0 and the words touched the border)
    assert tag["padding"] == "0 var(--app-source-tag-pad)"
    assert ALL_TOKENS["--app-source-tag-pad"] == "6px"
    #? both lines wrap on a narrow phone rather than run off it
    assert declarations(APP, ".app-source-signals")["flex-wrap"] == declarations(APP, ".app-source-tags")["flex-wrap"] == "wrap"


def test_other_pressings_never_gives_way_and_a_held_pressing_is_marked_green():
    #? the album page's chip row stays one line; "Other pressings" never shortens - the Also chips do
    assert "flex-wrap" not in declarations(APP, ".app-album-chips")
    assert declarations(APP, ".app-album-chips > .app-other-pressings") == {"flex": "none"}
    #? ...and is a chip, its reach unclipped
    assert "overflow" not in declarations(APP, ".app-other-pressings")
    #? beside an Also chip, in a row too narrow for the three whole: "Pressings", and the badge's words read
    #? but never shown (the visually-hidden rule's own declarations) - so the Also chip keeps room to say
    #? which pressing it is. By the ROW's width, a container query on the row itself (review: by the frame,
    #? a desktop's column narrowed by the Edit panel crushed the Also chip to a bare "›", and a phone on
    #? its side gave up words it had the room for)
    assert declarations(APP, ".app-album-chips")["container"] == "app-album-chips / inline-size"
    assert declarations(APP, ".app-other-short") == {"display": "none"}
    narrow = "@container app-album-chips (max-width: 600px)"
    assert declarations(APP, ".app-album-chips:has(.app-also) .app-other-long", narrow) == {"display": "none"}
    assert declarations(APP, ".app-album-chips:has(.app-also) .app-other-short", narrow) == {"display": "inline"}
    assert declarations(APP, ".app-album-chips:has(.app-also):has(.app-other-pressings) .app-held-badge-text", narrow) == declarations(APP, ".app-visually-hidden")
    #? ...never by the frame: no rule outside that query shortens them, and the desktop's stylesheet has none
    desk = (PLAYER / "app-desktop.css").read_text()
    for css in (APP, desk):
        for context, selector, _values in rules(css):
            if any(name in selector for name in (".app-other-long", ".app-held-badge-text")) or ".app-other-short" in selector and selector != ".app-other-short":
                assert context == narrow, (context, selector)
    #? the row's place held from the first frame, nothing in it shown until the bridge has answered - so
    #? the badge first shows where it stays, never sliding along a phone's centred row (review)
    assert declarations(APP, ".app-album-chips.is-waiting > *") == {"visibility": "hidden"}
    assert declarations(APP, ".app-album-chips")["justify-content"] == "center"
    held = declarations(APP, ".app-picker-held")
    assert (held["color"], held["font-size"]) == ("var(--dw-badge-green-text)", "var(--dw-text-label)")
    #? Search again centred under the line saying what was searched; the form it opens starts at once
    assert declarations(APP, ".app-sources-again") == {"display": "flex", "justify-content": "center"}
    assert declarations(APP, ".app-sources-state.is-again") == {"padding-top": "var(--app-sources-again-pad)"}
    #? ...its field focused as it opens, so its ring - drawn outside - shows every time: the label keeps
    #? room over it for the ring's width and its gap, and the label's own line gap (review: it touched)
    assert declarations(APP, ".app-sources-query-input:focus-visible")["outline-offset"] == "var(--app-ring)"
    assert declarations(APP, ".app-sources-query")["gap"] == "calc(var(--app-ring-room) + var(--app-line-gap))"
    assert ALL_TOKENS["--app-ring-room"] == "calc(2 * var(--app-ring))"


#? set inline by the components, never in a stylesheet: the turntable's stage's shape, and the speed
#? fader's place on the plinth
SET_INLINE = {"--app-tt-aspect": "player/Turntable.tsx", "--app-tt-fader-x": "player/SpeedFader.tsx", "--app-tt-fader-from": "player/SpeedFader.tsx"}


def test_every_token_a_rule_reads_is_defined():
    """
    A var() with no fallback naming a token nobody defines makes its whole declaration invalid when the
    page is drawn - a padding falls back to 0, and nothing says so (2.0.0-player.41's edition tags, found
    in review). Every token the app's stylesheets read is defined in one of the four, or set inline by
    the component that draws it.
    """
    desk = (PLAYER / "app-desktop.css").read_text()
    sheets = (THEME_CSS, PLAYER_CSS, APP, desk)
    defined = {name for css in sheets for _context, _selector, values in rules(css) for name in values if name.startswith("--")}
    read = {name for css in sheets for _context, _selector, values in rules(css) for value in values.values()
            for name in re.findall(r"var\((--[\w-]+)\)", value)}
    assert sorted(read - defined - set(SET_INLINE)) == []
    #? ...and each one said to be set inline is, by the component named - so the list can't outlive it
    ui = Path(__file__).resolve().parent.parent / "ui" / "src"
    for name, component in SET_INLINE.items():
        assert f"'{name}':" in (ui / component).read_text(), name


# ---------------------------------------------------------------- the artist page as the main page had it (2.0.0-player.45)

def test_the_artist_pages_panel_is_a_sheet_over_the_whole_screen_on_a_phone():
    """From the very top, its words clear of the status bar and its foot of the home indicator by padding,
    placed clear of a notch by left and right - never padded by it; its own scroll lock; the body the one
    part that scrolls, saying its touches pan; its asking bar stopped as it slides away."""
    assert declarations(APP, "html.app-artist-panel-open") == {"overflow": "hidden"}
    box = declarations(APP, ".app-artist-panel")
    assert (box["position"], box["top"], box["bottom"], box["right"], box["left"]) == ("absolute", "0", "0", "var(--pl-safe-right)", "var(--pl-safe-left)")
    assert box["padding"].startswith("calc(var(--pl-safe-top) + var(--app-artist-panel-pad))")
    assert "safe" not in box["padding"].split(" ", 2)[-1].replace("var(--pl-safe-top)", "")
    assert (box["transform"], declarations(APP, ".app-layer.is-open .app-artist-panel")["transform"]) == ("translateY(100%)", "translateY(0)")
    body = declarations(APP, ".app-artist-panel-body")
    assert (body["flex"], body["min-height"], body["overflow-y"], body["overflow-x"], body["touch-action"]) == ("1", "0", "auto", "hidden", "pan-y")
    foot = declarations(APP, ".app-artist-panel-foot")
    assert foot["padding"] == "var(--app-artist-panel-pad) 0 calc(var(--pl-safe-bottom) + var(--app-artist-panel-pad))"
    assert declarations(APP, ".app-artist-panel-layer:not(.is-open) .app-sweep::before") == {"animation-play-state": "paused"}


def test_the_artist_pages_panel_is_a_fingers_and_ios_never_zooms_into_its_search():
    close = declarations(APP, ".app-artist-panel-close")
    assert (close["width"], close["height"]) == ("var(--pl-hit)", "var(--pl-hit)")
    #? Move, Cancel, Save, Done and Search are the player's pills (48px)
    assert px("--pl-pill-height") >= px("--pl-hit")
    for selector in (".app-artist-panel-inline", ".app-artist-replace", ".app-artist-change"):
        assert declarations(APP, selector)["min-height"] == "var(--pl-hit)", selector
    field = declarations(APP, ".app-artist-search-input")
    assert (field["font-size"], field["min-height"]) == ("var(--dw-text-body)", "var(--pl-pill-height)")
    assert px("--dw-text-body") >= 16
    #? a row a match is: the grouped list's, a finger tall
    assert declarations(APP, ".app-row")["min-height"] == "var(--dw-row)" and px("--dw-row") >= px("--pl-hit")
    for selector in (".app-artist-move-path", ".app-artist-move-to", ".app-artist-match-name", ".app-artist-panel-note"):
        assert declarations(APP, selector)["overflow-wrap"] == "anywhere", selector
    assert declarations(APP, ".app-artist-panel-said")["min-height"] == "var(--app-artist-said)"
    assert ALL_TOKENS["--app-artist-said"] == "calc(var(--dw-text-footnote) * var(--dw-leading-note))"


def test_the_artist_page_draws_its_logo_its_managing_and_its_facts_as_said():
    logo = declarations(APP, ".app-artist-logo")
    assert (logo["max-width"], logo["max-height"], logo["object-fit"]) == ("100%", "var(--app-artist-logo)", "contain")
    #? Artist images… and the rest are the app's secondary button - a finger tall - toggled while the
    #? panel shows them, and stepped back while they can't be used (aria-disabled: still focusable)
    assert declarations(APP, ".app-button")["min-height"] == "var(--dw-row)"
    pressed = declarations(APP, ".app-artist-manage-button[aria-pressed='true']")
    assert (pressed["background"], pressed["color"]) == ("var(--dw-toggled-bg)", "var(--dw-accent-text)")
    assert declarations(APP, ".app-artist-manage-button[aria-disabled='true']") == {"opacity": "var(--app-pin-off)"}
    folder = declarations(APP, ".app-artist-folder")
    assert (folder["white-space"], folder["overflow-wrap"], folder["font-family"]) == ("pre-line", "anywhere", "var(--dw-font-mono)")
    assert declarations(APP, ".app-row.app-artist-link")["flex-wrap"] == "nowrap"
    assert declarations(APP, ".app-artist-link-label")["overflow-wrap"] == "anywhere"
    #? a fold is the app's text button, a finger tall, whatever its words
    assert declarations(APP, ".app-text-button")["min-height"] == "var(--dw-row)" and "min-height" not in declarations(APP, ".app-artist-fold")
    past = declarations(APP, ".app-artist-member.is-past .app-artist-member-text")
    assert past == {"opacity": "var(--app-artist-past)"} and ALL_TOKENS["--app-artist-past"] == "0.6"


def test_the_artist_pages_panel_keeps_a_footless_body_clear_of_the_home_indicator():
    """Review: Which artist is this? has no foot, and the foot's padding was the sheet's only clearance -
    its last match sat under the home indicator. Its end is padded as Info's and the Sources sheet's are."""
    assert declarations(APP, ".app-artist-panel-body:last-child")["padding-bottom"] == "calc(var(--pl-safe-bottom) + var(--pl-gutter))"
    assert declarations(APP, ".app-info-scroll")["padding-bottom"] == "calc(var(--pl-safe-bottom) + var(--pl-gutter))"


def test_the_artist_pages_panel_scrolls_as_one_on_a_phone_on_its_side():
    """Review: at 844x390 the fixed head and foot left the pictures about 140px. Under 500px tall the sheet
    scrolls as one - its touches panning it - and the body grows with what it holds."""
    short = "@media (max-height: 500px)"
    box = declarations(APP, ".app-artist-panel", short)
    assert (box["overflow-y"], box["overflow-x"], box["touch-action"], box["overscroll-behavior"]) == ("auto", "hidden", "pan-y", "contain")
    assert declarations(APP, ".app-artist-panel-body", short) == {"flex": "none", "overflow": "visible"}


def test_a_picture_to_choose_sits_in_a_box_of_its_slots_shape():
    """Review: the box followed each picture's shape as it loaded (lazily, full size from fanart.tv), so the
    options after it moved and wrapped under a finger. Square slots square, every other wide, fitted inside."""
    image = declarations(APP, ".app-artist-option-image")
    assert (image["width"], image["height"], image["object-fit"]) == ("var(--app-artist-option-wide)", "var(--app-artist-option)", "contain")
    assert not {"min-width", "max-width"} & set(image)
    assert declarations(APP, ".app-artist-option-image.is-square") == {"width": "var(--app-artist-option)"}
    assert px("--app-artist-option-wide") > px("--app-artist-option")


# ---------------------------------------------------------------- inside a track (2.0.0-player.44)

UI = Path(__file__).resolve().parent.parent / "ui" / "src"


def test_the_cover_viewer_covers_the_window_on_both_frames_over_everything_but_the_notice():
    viewer = declarations(APP, ".app-viewer #art-viewer")
    assert (viewer["position"], viewer["inset"], viewer["z-index"], viewer["touch-action"]) == ("fixed", "0", "var(--app-z-viewer)", "none")
    #? over Now Playing (20), Sources (25), Info and the Edit panel (30) - under the pin notice (40)
    z = int(ALL_TOKENS["--app-z-viewer"])
    assert int(ALL_TOKENS["--app-z-over"]) < z < int(ALL_TOKENS["--app-z-notice"])
    assert int(ALL_TOKENS["--app-z-sources"]) < z
    for side in ("--pl-safe-top", "--pl-safe-right", "--pl-safe-bottom", "--pl-safe-left"):
        assert f"var({side})" in viewer["padding"], side
    #? the image is moved and zoomed by the viewer's own transform, clipped by its stage
    assert declarations(APP, ".app-viewer .art-viewer-stage")["overflow"] == "hidden"
    assert declarations(APP, ".app-viewer .art-viewer-stage > img")["touch-action"] == "none"
    #? a phone's whole screen - and a desktop's the panel's viewer's size (app-desktop.css)
    assert (ALL_TOKENS["--app-viewer-max"], ALL_TOKENS["--app-viewer-height"]) == ("100%", "100%")


def test_the_cover_viewer_has_its_own_scroll_lock_and_tells_a_hand_it_can_pinch():
    assert declarations(APP, "html.app-viewer-open")["overflow"] == "hidden"
    viewer = (UI / "app" / "CoverViewer.tsx").read_text()
    assert "export const VIEWER_LOCK = 'app-viewer-open'" in viewer
    assert re.search(r"page\.classList\.add\(VIEWER_LOCK\)\s*return \(\) => page\.classList\.remove\(VIEWER_LOCK\)", viewer)
    assert declarations(APP, ".app-viewer .hint-touch")["display"] == "none"
    coarse = "@media (pointer: coarse)"
    assert declarations(APP, ".app-viewer .hint-pointer", coarse)["display"] == "none"
    assert declarations(APP, ".app-viewer .hint-touch", coarse)["display"] == "inline"


def test_the_cover_viewers_buttons_are_tap_targets_with_their_rings_inside():
    close = declarations(APP, ".app-viewer .window-close")
    assert (close["width"], close["height"]) == ("var(--pl-hit)", "var(--pl-hit)")
    assert declarations(APP, ".app-viewer .win-button")["min-height"] == "var(--pl-hit)"
    for selector in (".app-viewer .window-close:focus-visible", ".app-viewer .win-button:focus-visible"):
        assert declarations(APP, selector)["outline-offset"] == "var(--app-ring-inset)", selector
    #? a label typed by whoever made the file breaks rather than running off the frame
    assert declarations(APP, ".app-viewer .art-viewer-label")["overflow-wrap"] == "anywhere"


def test_an_album_pages_cover_is_a_button_with_the_hero_covers_class():
    page = (UI / "player" / "AlbumPage.tsx").read_text()
    assert 'class="pl-hero-cover app-cover-open"' in page and '<Cover id={shown.coverArt} size={800} class="app-cover-open-img" />' in page
    picture = declarations(APP, ".app-cover-open-img")
    assert (picture["width"], picture["height"], picture["object-fit"]) == ("100%", "100%", "cover")
    assert declarations(APP, ".app-cover-open")["overflow"] == "hidden"
    assert declarations(APP, ".app-cover-open:active .app-cover-open-img")["opacity"] == "var(--dw-pressed-cover)"


def test_the_track_inspector_fits_a_390px_panel():
    fields = declarations(APP, ".app-inspect-fields")
    assert fields["grid-template-columns"] == "minmax(0, var(--app-inspect-label)) minmax(0, 1fr)"
    for selector in (".app-inspect-value", ".app-inspect-label", ".app-inspect-title", ".app-inspect-words",
                     ".app-inspect-picture-label", ".app-inspect-picture-facts", ".app-inspect-file"):
        assert declarations(APP, selector)["overflow-wrap"] == "anywhere", selector
    for selector in (".app-inspect-value", ".app-inspect-label", ".app-inspect", ".app-inspect-group", ".app-inspect-picture-words"):
        assert declarations(APP, selector)["min-width"] == "0", selector
    #? a 390px panel, its 20px padding either side (the desktop's --app-desk-panel-pad): the value column
    #? keeps 200px - a MusicBrainz id in two lines, never one character a line
    assert 390 - 2 * 20 - px("--app-inspect-label") - px("--app-inspect-col-gap") >= 200
    assert declarations(APP, ".app-inspect-actions")["flex-wrap"] == "wrap"
    assert declarations(APP, ".app-inspect-picture")["width"] == "100%"


def test_the_inspectors_controls_are_tap_targets_with_their_rings_drawn_inside():
    for selector in (".app-inspect-button", ".app-inspect-picture", ".app-inspect-summary", ".app-edit-track-open"):
        assert declarations(APP, selector)["min-height"] == "var(--pl-hit)", selector
    for selector in (".app-inspect-button:focus-visible", ".app-inspect-picture:focus-visible",
                     ".app-inspect-summary:focus-visible", ".app-edit-track-open:focus-visible",
                     #? (review) Artwork's cover and its first CD art picture sit on the panel body's left edge
                     ".app-edit-cover-open:focus-visible", ".app-edit-disc:focus-visible"):
        assert declarations(APP, selector)["outline-offset"] == "var(--app-ring-inset)", selector
    #? the end of the album: still a stop for the keyboard, seen to refuse
    assert declarations(APP, ".app-inspect-button[aria-disabled='true']")["opacity"] == "var(--app-inspect-off)"
    #? what isn't in the file, and the inferred disc 1: quieter than what is
    for selector in (".app-inspect-value.is-empty", ".app-inspect-value.is-inferred"):
        assert declarations(APP, selector)["color"] == "var(--dw-text-3)", selector
    name = declarations(APP, ".app-edit-track-open")
    assert (name["text-overflow"], name["white-space"], name["width"]) == ("ellipsis", "nowrap", "100%")


def test_an_album_pages_properties_break_a_release_id_and_reach_a_finger():
    rows = declarations(APP, ".app-props-list")
    assert rows["grid-template-columns"] == "minmax(0, var(--app-props-label)) minmax(0, 1fr)"
    value = declarations(APP, ".app-props-value")
    assert (value["overflow-wrap"], value["min-width"]) == ("anywhere", "0")
    link = declarations(APP, ".app-props-link")
    assert (link["padding"], link["margin"]) == ("var(--app-props-link-reach) 0", "calc(-1 * var(--app-props-link-reach)) 0")
    #? (review) its line is the list's, worked out from the tokens the list is set in - no number typed here
    assert (rows["font-size"], rows["line-height"]) == ("var(--dw-text-footnote)", "var(--dw-leading-note)")
    assert ALL_TOKENS["--app-props-link-line"] == "calc(var(--dw-text-footnote) * var(--dw-leading-note))"
    line = px("--dw-text-footnote") * float(ALL_TOKENS["--dw-leading-note"])
    assert round(length("--app-props-link-line"), 6) == round(line, 6)
    #? ...its line plus the reach above and below: a finger's height, the whole of it
    assert round(2 * length("--app-props-link-reach") + line, 6) >= px("--pl-hit")
    #? ...never under it, whatever the layout's rounding of a 18.2px line and a 12.9px reach (a hair short)
    assert link["min-height"] == "var(--pl-hit)"
    #? ...and all of it hit: positioned, so drawn over the rows either side, never under the next row (a
    #? grid item drawn after it, which took the bottom of the reach)
    assert link["position"] == "relative"


# ---------------------------------------------------------------- looking after deadwax from a phone (2.0.0-player.47)

PHONE = ".app-shell:not(.app-desk)"
PHONE_HEADING = "/* ===== looking after deadwax from a phone (2.0.0-player.47)"


def section(css: str, heading: str) -> str:
    """A section of a stylesheet: from its heading to the next section's (`/* ===== `), or to the end of the
    file while it is the last - so a section appended after it is never held to its rules."""
    start = css.index(heading)
    end = css.find("/* ===== ", start + len(heading))
    return css[start:] if end == -1 else css[start:end]


#? the section of app.css the change wrote
PHONE_SECTION = section(APP, PHONE_HEADING)


def phone(selector: str, context: str = "") -> dict[str, str]:
    """A rule of the phone's frame alone - `.app-shell:not(.app-desk) <selector>`."""
    return declarations(APP, f"{PHONE} {selector}", context)


def test_the_phones_managing_rules_never_reach_the_desktop():
    """Every rule the phone's managing added sits under the phone's frame (App puts `.app-desk` on the shell
    from 1024px) - or is the sheet's scroll lock, or scroll padding a phone's page alone can set - so the
    desktop's rules for the same parts (app-desktop.css) are all that draw them there, as before."""
    found = rules(PHONE_SECTION)
    assert len(found) > 150
    for context, selector, _values in found:
        for part in (piece.strip() for piece in selector.split(",")):
            assert (part == ":root" or part.startswith(f"{PHONE} ") or part.startswith(".app-shell.has-mini:not(.app-desk) ")
                    or part == "html.app-edit-open" or part.startswith(f"html:has({PHONE} ")
                    or part.startswith("html:has(.app-shell.has-mini:not(.app-desk) ")), (context, part)
    #? ...and the release editor's own cover viewer, styled as the album page's (the rules it shares), the same way
    viewer = [part.strip() for _context, selector, _values in rules(APP) for part in selector.split(",") if "#app-edit-panel-release" in part]
    assert viewer and all(part.startswith(f"{PHONE} #app-edit-panel-release ") for part in viewer), viewer
    assert phone("#app-edit-panel-release #art-viewer")["position"] == "fixed"
    assert phone("#app-edit-panel-release .window-close")["width"] == "var(--pl-hit)"


def test_every_id_and_class_the_phones_section_styles_is_still_in_the_markup():
    """(review) The sheet styles the main page's editors by their own ids and classes - MetadataEditor's
    #metadata-footer, TrackTagEditor's .tags-footer (the sticky Apply bars), DeleteAlbumDialog's, the settings'
    rows - so renaming one in its component, and checking the main page and the desktop's panel, would leave
    the phone's rule matching nothing with every other test green: each name is held to the source here."""
    ui = Path(__file__).resolve().parent.parent / "ui" / "src"
    source = "\n".join(path.read_text() for path in sorted(ui.rglob("*.ts*")))
    names = {match.group(1) for _context, selector, _values in rules(PHONE_SECTION)
             for match in re.finditer(r"[#.]([A-Za-z][\w-]*)", selector)}
    #? the log's stream state, built `is-${stream}` from StreamState's words
    built = {"is-live", "is-lost"}
    assert "app-log-stream is-${stream}" in (ui / "app" / "EventLog.tsx").read_text()
    assert "'live' | 'lost'" in (ui / "lib" / "eventLog.ts").read_text()
    gone = sorted(name for name in names - built if not re.search(rf"(?<![\w-]){re.escape(name)}(?![\w-])", source))
    assert gone == []
    #? ...the load-bearing ones by name, where they are drawn
    components = ui / "components"
    for name, file in (("metadata-footer", "MetadataEditor.tsx"), ("metadata-apply-button", "MetadataEditor.tsx"), ("tags-footer", "TrackTagEditor.tsx"),
                       ("tags-apply-button", "TrackTagEditor.tsx"), ("delete-confirm-button", "DeleteAlbumDialog.tsx"), ("settings-env-input", "SettingsView.tsx")):
        assert name in names and name in (components / file).read_text(), name


def test_the_phones_section_ends_where_the_next_begins():
    """(review) The section is held to the phone's frame up to the next section's heading, not to the end of the
    file: a later change appending an ordinary rule to app.css is never told it must sit under the phone's frame."""
    later = APP + "\n/* ===== a later change (2.0.0-player.99) ===== */\n.app-later { color: var(--dw-text); }\n"
    held = section(later, PHONE_HEADING)
    assert ".app-later" not in held and held.rstrip() == PHONE_SECTION.rstrip()
    #? ...and nothing of the section is lost: its last rule is still in it, and nothing follows it today
    assert PHONE_SECTION.rstrip().endswith("}") and APP.rstrip().endswith(PHONE_SECTION.rstrip())


def test_the_edit_panel_is_a_sheet_over_the_whole_screen_on_a_phone():
    """As the artist page's panel: from the very top, its words clear of the status bar by padding, placed clear
    of a notch by left and right; its own scroll lock; no transform once open (the cover viewers inside it are
    fixed to the screen, not to it); the body the one part that scrolls, saying its touches pan."""
    ui = Path(__file__).resolve().parent.parent / "ui" / "src"
    assert "lockClass: 'app-edit-open'" in (ui / "app" / "EditPanel.tsx").read_text()
    assert declarations(APP, "html.app-edit-open") == {"overflow": "hidden"}
    box = phone(".app-edit")
    assert (box["position"], box["top"], box["bottom"], box["right"], box["left"]) == ("absolute", "0", "0", "var(--pl-safe-right)", "var(--pl-safe-left)")
    assert box["padding"].startswith("calc(var(--pl-safe-top) + var(--app-ph-pad))")
    assert (box["transform"], phone(".app-layer.is-open .app-edit")["transform"]) == ("translateY(100%)", "none")
    body = phone(".app-edit-body")
    assert (body["flex"], body["min-height"], body["overflow-y"], body["overflow-x"], body["touch-action"]) == ("1", "0", "auto", "hidden", "pan-y")
    #? a tab's end clear of the home indicator - but one whose Apply bar clears it itself
    assert phone(".app-edit-pane")["padding-bottom"] == "calc(var(--pl-safe-bottom) + var(--app-ph-pad))"
    assert phone(".app-edit-pane:has(#metadata-footer)")["padding-bottom"] == phone(".app-edit-pane:has(.tags-footer)")["padding-bottom"] == "0"
    assert phone(".app-edit-layer:not(.is-open) .app-sweep::before") == {"animation-play-state": "paused"}


def test_the_edit_sheets_targets_are_a_fingers_and_ios_never_zooms_into_its_fields():
    """Every field 17px and a finger tall (iOS zooms into one under 16); the close button, the tabs, a tick box's
    label, a folder to choose, a pressing, every button of the hosted editors - and Apply - 44px."""
    assert px("--dw-text-body") >= 16 and px("--pl-hit") == 44
    for selector in (".app-edit .releases-filter-input", ".app-edit-select", ".app-edit-pick-input"):
        field = phone(selector)
        assert (field["font-size"], field["min-height"]) == ("var(--dw-text-body)", "var(--pl-hit)"), selector
    close = phone(".app-edit-close")
    assert (close["width"], close["height"]) == ("var(--pl-hit)", "var(--pl-hit)")
    for selector in (".app-edit-tab", ".app-edit-choice", ".app-edit .app-edit-button", ".app-edit .columns-toggle-button", ".app-edit .win-button",
                     ".app-edit #metadata-apply-button", ".app-edit #tags-apply-button", ".app-edit #delete-confirm-button", ".app-edit .metadata-release",
                     ".app-edit .metadata-issue-undo", ".app-edit .tags-revert", ".app-edit .tags-tracks > summary", ".app-edit .metadata-checkbox"):
        assert phone(selector)["min-height"] == "var(--pl-hit)", selector
    hit = phone(".app-edit-hit")
    assert (hit["min-width"], hit["min-height"]) == ("var(--pl-hit)", "var(--pl-hit)")
    assert phone(".app-edit-tracks .app-edit-tick")["width"] == "var(--pl-hit)"
    assert phone(".app-edit #tags-window .window-close")["width"] == "var(--pl-hit)"
    #? the tabs: spread across where they fit, scrolling sideways (by themselves) where they don't - saying
    #? they pan sideways inside the sheet alone, whose layer takes every touch (review: Server settings' row,
    #? the same class in the page's own scroll, stopped a swipe up that began on it from scrolling the page)
    tabs = phone(".app-edit-tabs")
    assert (tabs["overflow-x"], phone(".app-edit-tab")["flex"]) == ("auto", "1 0 auto")
    assert phone(".app-edit .app-edit-tabs") == {"touch-action": "pan-x"}
    assert not [selector for _context, selector, values in rules(APP) if "touch-action" in values
                and any(part in selector for part in (".app-edit-tabs", ".app-settings-tabs", ".app-settings-tab")) and ".app-edit .app-edit-tabs" not in selector]
    #? the sheet's own ✕ stands for the release editor's
    assert phone(".app-edit #metadata-close-button") == {"display": "none"}


def test_the_edit_sheets_apply_stays_in_reach_above_the_home_indicator():
    """The release editor's and the tag editor's Apply bars stick to the foot of the sheet's scroll, their own
    foot padded clear of the home indicator, Cancel and Apply whole buttons across it; the solid purple is
    Apply's, the red the delete's."""
    for selector in (".app-edit #metadata-footer", ".app-edit .tags-footer"):
        foot = phone(selector)
        assert (foot["position"], foot["bottom"], foot["background"]) == ("sticky", "0", "var(--dw-bg-sheet)"), selector
        assert foot["padding"] == "var(--app-ph-block) 0 calc(var(--pl-safe-bottom) + var(--app-ph-block))", selector
    assert phone(".app-edit #metadata-footer > button")["flex"] == "1 1 auto"
    assert phone(".app-edit #metadata-apply-button")["background"] == "var(--dw-primary-bg)"
    #? the viewer's own choice: the primary, outweighing the viewer's secondary button by the release tab's id
    assert phone("#app-edit-panel-release .win-button.is-default")["background"] == "var(--dw-primary-bg)"
    assert phone(".app-edit #delete-confirm-button")["background"] == "var(--dw-danger-bg)"
    #? the pressings in the sheet's own scroll: no list scrolling inside another on a phone
    assert "max-height" not in phone(".app-edit .metadata-releases") and "overflow-y" not in phone(".app-edit .metadata-releases")


def test_the_release_editors_preview_is_readable_at_320px():
    """A change: the tag's name on a line of its own, the old value (struck) and the new side by side under it -
    three columns at 288px would leave each a word or two wide. Long names and paths broken, never clipped."""
    change = phone(".app-edit .metadata-change")
    assert change["grid-template-columns"] == "minmax(0, 1fr) minmax(0, 1fr)"
    assert phone(".app-edit .metadata-tag")["grid-column"] == "1 / -1"
    assert phone(".app-edit .metadata-from")["text-decoration"] == "line-through"
    for selector in (".app-edit .metadata-from", ".app-edit .metadata-to", ".app-edit .metadata-tag", ".app-edit .metadata-path", ".app-edit .metadata-file-name",
                     ".app-edit .metadata-move", ".app-edit-note", ".app-edit-choice", ".app-edit .delete-others", ".app-edit .metadata-release-title"):
        assert phone(selector)["overflow-wrap"] == "anywhere", selector


def test_on_a_phone_on_its_side_the_edit_sheets_title_sits_beside_its_tabs():
    """At 844x390 a second row of head over the tabs left the body - and the Apply bar at its foot - too little:
    under 500px tall the head and its close button sit beside the tabs, the body the rest."""
    short = "@media (max-height: 500px)"
    box = phone(".app-edit", short)
    assert (box["display"], box["grid-template-columns"], box["grid-template-rows"]) == ("grid", "minmax(0, 1fr) auto", "auto auto minmax(0, 1fr)")
    assert (phone(".app-edit-head", short)["grid-area"], phone(".app-edit-tabs", short)["grid-area"], phone(".app-edit-body", short)["grid-area"]) == (
        "1 / 2 / 2 / 3", "1 / 1 / 2 / 2", "3 / 1 / 4 / 3")


def test_an_album_pages_edit_on_a_phone_is_in_its_bar_and_reaches_44px():
    """In the bar beside the pin, the pin's size, its reach a finger's every way; pushed to the bar's right by
    its margin, the back link giving way; toggled while the sheet shows the album, faded until it answers."""
    chip = phone(".app-edit-chip")
    assert (chip["height"], chip["margin-left"], chip["position"]) == ("var(--app-pin-toggle)", "auto", "relative")
    assert phone(".app-edit-chip::before")["inset"] == "calc(-1 * var(--app-pin-toggle-reach))"
    assert length("--app-pin-toggle") + 2 * length("--app-pin-toggle-reach") >= px("--pl-hit")
    assert phone('.app-edit-chip[aria-pressed="true"]')["background"] == "var(--dw-toggled-bg)"
    assert phone(".app-edit-chip:disabled")["opacity"] == "var(--app-pin-off)"
    assert declarations(APP, ".app-album-bar .pl-back")["min-width"] == "0"


def test_the_managing_pages_on_a_phone_are_a_fingers_and_never_zoom():
    """Needs a look's rows, Library care's field and buttons, the settings' fields, revert and save bar - a
    finger's, 17px fields; the facets the Library's chips (a finger's reach) within the page's edges."""
    for selector in (".app-settings .settings-env-input", ".app-care-input"):
        field = phone(selector)
        assert (field["font-size"], field["min-height"]) == ("var(--dw-text-body)", "var(--pl-hit)"), selector
    for selector in (".app-queue-row", ".app-queue-checking", ".app-settings .settings-env-revert", ".app-settings-discard", ".app-settings-save",
                     ".app-settings .settings-retime .win-button", ".app-care .app-text-button"):
        assert phone(selector)["min-height"] == "var(--pl-hit)", selector
    #? Library care's buttons and Try again are the app's secondary button, a finger tall on both frames
    assert declarations(APP, ".app-button")["min-height"] == "var(--dw-row)" and px("--dw-row") >= px("--pl-hit")
    #? each page's body within the page's edges
    for selector in (".app-queue-body", ".app-settings-body", ".app-log-body", ".app-care-body"):
        assert phone(selector)["padding"] == "0 var(--pl-edge-right) var(--pl-gap) var(--pl-edge-left)", selector
    #? a row of Needs a look: its cover beside its name and artist, its chips under them wrapping, whole
    row = phone(".app-queue-row")
    assert (row["display"], row["grid-template-columns"]) == ("grid", "var(--app-ph-queue-cover) minmax(0, 1fr)")
    assert phone(".app-queue-cover")["grid-row"] == "1 / span 2"
    assert (phone(".app-queue-chips")["flex-wrap"], phone(".app-queue-chip")["text-overflow"]) == ("wrap", "ellipsis")
    assert phone(".app-queue-row.is-done .app-queue-text")["opacity"] == "var(--app-ph-queue-done)"
    assert phone(".app-queue-row.is-current")["background"] == "var(--dw-selection-bg)"
    #? the settings' rows wrap: a key broken anywhere over its field
    assert phone(".app-settings .settings-env")["flex-direction"] == "column"
    assert phone(".app-settings .settings-env-key")["overflow-wrap"] == "anywhere"


def test_the_settings_save_bar_on_a_phone_sits_above_the_tab_bar_and_the_mini_player():
    """Sticky above the tab bar - and the mini player while it shows - taking no taps until it says something;
    keyboard focus (and a field the keyboard comes up for) kept clear of it while it does, only from the pane
    that shows. Its words over Discard and Save, each half the width."""
    bar = phone(".app-settings-savebar")
    assert (bar["position"], bar["bottom"], bar["z-index"]) == ("sticky", "var(--app-tabbar-height)", "var(--app-ph-z-bar)")
    assert declarations(APP, ".app-shell.has-mini:not(.app-desk) .app-settings-savebar")["bottom"] == "var(--app-ph-bar-mini)"
    assert ALL_TOKENS["--app-ph-bar-mini"] == "calc(var(--app-tabbar-height) + var(--pl-mini-height) + var(--pl-mini-inset))"
    assert phone(".app-settings-savebar:not(.is-said)") == {"pointer-events": "none"}
    assert phone(".app-settings-savebar.is-said")["background"] == "var(--dw-bg)"
    padded = declarations(APP, f"html:has({PHONE} .app-pane:not([hidden]) .app-settings-savebar.is-said)")
    assert padded["scroll-padding-bottom"] == "calc(var(--app-chrome-bottom) + var(--app-ph-bar) + var(--dw-hairline))"
    mini = declarations(APP, "html:has(.app-shell.has-mini:not(.app-desk) .app-pane:not([hidden]) .app-settings-savebar.is-said)")
    assert mini["scroll-padding-bottom"] == "calc(var(--app-chrome-bottom-mini) + var(--app-ph-bar) + var(--dw-hairline))"
    #? the bar's height the padding reads: its words' line over a finger's buttons
    assert ALL_TOKENS["--app-ph-bar"] == "calc(2 * var(--app-ph-bar-pad) + var(--app-ph-bar-line) + var(--app-ph-lines) + var(--pl-hit))"
    assert phone(".app-settings-savebar-text")["flex"] == "1 1 100%"
    assert (phone(".app-settings-discard")["flex"], phone(".app-settings-save")["background"]) == ("1 1 0", "var(--dw-primary-bg)")
    #? a window wide enough (a phone on its side, an iPad upright): one line - and the padding the shorter bar's
    wide = "@media (min-width: 600px)"
    assert declarations(APP, ":root", wide)["--app-ph-bar"] == "calc(2 * var(--app-ph-bar-pad) + var(--pl-hit))"
    assert phone(".app-settings-savebar-text", wide)["flex"] == "1 1 0"
    assert phone(".app-settings-discard", wide)["flex"] == phone(".app-settings-save", wide)["flex"] == "0 0 var(--app-ph-bar-button)"


def test_the_log_on_a_phone_wraps_its_lines_and_the_care_runs_words_are_drawn_while_empty():
    """A line's time, level and source over its words, which take the row's width and break anywhere; errors
    red and warnings amber. Library care's run result drawn while empty (a live region VoiceOver reads only
    once it is there), giving its gap back."""
    line = phone(".app-log-row")
    assert (line["display"], line["grid-template-columns"]) == ("grid", "auto auto minmax(0, 1fr)")
    words = phone(".app-log-words")
    assert (words["grid-column"], words["overflow-wrap"]) == ("1 / -1", "anywhere")
    assert phone(".app-log-row.is-error .app-log-words")["color"] == "var(--dw-danger-text)"
    assert phone(".app-log-row.is-warning .app-log-words")["color"] == "var(--dw-amber-text)"
    assert phone(".app-care-result:empty")["margin-top"] == "calc(-1 * var(--app-ph-lines))"
    assert "display" not in phone(".app-care-result")
