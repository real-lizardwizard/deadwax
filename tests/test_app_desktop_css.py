"""
The desktop frame's stylesheet at /player/ (2.0.0-player.19), interface/player/app-desktop.css, and
the desktop's values for theme.css's tokens - read as rules, as tests/test_app_css.py reads app.css.

- THE PHONE APP IS UNCHANGED BELOW 1024px. Every rule in app-desktop.css sits inside a media query
  from 1024px (or 1280px), and every selector but html's and :root's is under `.app-desk` - the class
  App puts on the shell only in the desktop frame. The breakpoints are lib/appFrame.ts's own
  constants, so the markup's frame (matchMedia) and the styles' can never disagree.
- The desktop's look is the same tokens redefined in a media query (theme.css section 10): labels
  11px, headings 13px, data 12px, cards #1e1c26, the page #0b0a10 - and body text left alone, since
  text fields read it and an iPad on its side is 1024px wide (iOS zooms into a field under 16px).
- Tokens only, as app.css: no raw length, time, line height, opacity or filter in a rule.
- The frame as DesktopLibrary.dc.html draws it: a 232px sidebar, a 72px player bar, the page given
  room for both; Sources and Info a 470px panel beside the page - never over the bar, no backdrop,
  a third column making room (`.has-side`) and appearing in place, a drawer sliding over the page.
- What the slice draws as its boards do: six covers across in the Library's grid and Home's shelf, the
  scrubber's clocks at its ends in the bar, Get in the toggled tint while the panel shows its
  sources, the tracklist's "Against the usual tracklist" column 190px, a source's facts in five
  columns with Speed the first, and the sidebar's field at the phone's size for a coarse pointer.
- And what its review found (2.0.0-player.19): the player bar's and the sidebar's class names their
  own (`.app-bar` was a job's progress track too, and every one of them was fixed to the foot of the
  screen); every target a finger's 44px where the pointer is coarse, the bar tall enough to hold the
  transport over the scrubber; the against column's note text an ellipsis shortens, not a box it
  hides; the pressing never wider than its row; a source's facts never over each other; the grids
  keeping a cover's size beside a third column; the album you don't have's Get and pressing under
  its cover, clear of a drawer, until 1280px; and a panel's box focusable by a click, with no ring.
- The full-screen visualizer (2.0.0-player.20) as DesktopVisualizer.dc.html draws it: a fixed layer
  over the whole window and over everything the app draws, its canvases filling it (one hidden by the
  attribute); its controls over a scrim at the top and the foot, taking the pointer only where there is
  a control, fading together - the pointer too - as the screen goes still, in about half a second (and
  at once under reduced motion); the song taking only what the choices leave, so they keep one row
  from 1280px and wrap only at a narrow desktop, leaving "now:" and "feel:" out until 1280px; play/pause
  a primary button at the foot; a note at the foot kept to its corner, clear of play/pause and the keys;
  and its controls a finger's size where the pointer is coarse.
- And the Edit panel (2.0.0-player.21, DesktopManage.dc.html): a third side panel by the same rule; the
  board's underline tabs and the album page's Edit toggled while it shows; the main page's editors
  drawn inside it styled by their own ids under `.app-desk .app-edit` (their own close hidden, Apply the
  solid purple at the board's 36px, delete the one red button); the cover viewer over the whole window;
  the pressings scrolling inside the panel with Apply kept in reach; and a finger's targets, and fields
  iOS won't zoom into, where the pointer is coarse. After review: the album page's Play, Shuffle and
  Edit under its cover while a drawer is open (Edit's own drawer would cover it); a tag's long name
  broken inside its column; busy words in a solid button the button's white; a pressing's track count
  on its first line; long names broken, never clipped; and a tick box's label a finger's target.
- Needs a look (2.0.0-player.25), with no board: rows at the frame's row height (a finger's where the
  pointer is coarse), the chips giving way before the album's name and never cut to a stub, the row the
  panel has open in Explorer's selection, a row dealt with faded but never its word, the quiet
  "Checking the library…" in a line always a row tall, the list clear of a drawer, and no solid purple.
- Server settings and the log (2.0.0-player.33), with no board: the page at least the page area's height
  and its save bar sticky at the foot above the player bar, taking no clicks while it says nothing and
  keeping keyboard focus clear of it while it says something, Save its one solid purple button; the
  settings tab's own rows styled by
  their own class names under `.app-settings` (this page loads no main.css); fields iOS won't zoom into
  and a finger's targets where the pointer is coarse; the log's words broken anywhere, its errors red and
  warnings amber; long values and paths broken, never run out; both pages clear of a drawer.
"""

import re
from pathlib import Path

from tests.test_app_css import LOOK_PROPERTIES, RAW_LENGTH, declarations, rules, tokens

REPO = Path(__file__).resolve().parent.parent
DESKTOP = (REPO / "interface" / "player" / "app-desktop.css").read_text()
THEME = (REPO / "interface" / "styles" / "theme.css").read_text()
FRAME = (REPO / "ui" / "src" / "lib" / "appFrame.ts").read_text()
APP = (REPO / "interface" / "player" / "app.css").read_text()
SRC = REPO / "ui" / "src"

DESK = "@media (min-width: 1024px)"
COLUMN = "@media (min-width: 1280px)"
COARSE = "@media (min-width: 1024px) and (pointer: coarse)"


def constant(name: str) -> int:
    found = re.search(rf"export const {name} = (\d+)\b", FRAME)
    assert found, f"lib/appFrame.ts has no {name}"
    return int(found.group(1))


def media_tokens(css: str, context: str) -> dict[str, str]:
    merged: dict[str, str] = {}
    for where, selector, values in rules(css):
        if where == context and selector == ":root":
            merged.update({name: value for name, value in values.items() if name.startswith("--")})
    return merged


def test_the_breakpoints_are_the_frames_own():
    assert constant("DESKTOP_MIN") == 1024
    assert constant("COLUMN_MIN") == 1280
    contexts = {where for where, _selector, _values in rules(DESKTOP)}
    assert contexts == {DESK, COARSE, COLUMN}
    for where in contexts:
        widths = [int(width) for width in re.findall(r"min-width: (\d+)px", where)]
        assert widths and min(widths) >= constant("DESKTOP_MIN"), where
    assert f"(min-width: {constant('COLUMN_MIN')}px)" in COLUMN


def test_nothing_reaches_the_phone():
    """No rule outside a media query from 1024px, and none outside the desktop frame's class - `html` alone,
    or `html` holding something inside the frame (`html:has(.app-desk ...)`, which only a desktop has)."""
    for where, selector, _values in rules(DESKTOP):
        assert where, f"{selector} is outside every media query - it would reach the phone"
        for part in selector.split(","):
            part = part.strip()
            assert part in (":root", "html") or part.startswith(".app-desk") or part.startswith("html:has(.app-desk "), part


def test_the_desktop_stylesheet_draws_only_from_tokens():
    raw = []
    for _context, selector, values in rules(DESKTOP):
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


def test_the_desktop_redefines_the_looks_tokens_in_a_media_query_never_the_phones():
    desk = media_tokens(THEME, DESK)
    #? the plan's three, and the rest of STYLE.md's desktop scale
    assert desk["--dw-text-label"] == "11px"
    assert desk["--dw-text-heading"] == "13px"
    assert desk["--dw-card"] == "#1e1c26"
    assert desk["--dw-bg"] == "#0b0a10"
    assert desk["--dw-text-data"] == "12px"
    assert (desk["--dw-text-large-title"], desk["--dw-text-title"]) == ("28px", "30px")
    #? text fields read it: an iPad on its side is a desktop, and iOS zooms into a field under 16px
    assert "--dw-text-body" not in desk
    #? the phone's own values stand
    phone = {name: value for where, selector, values in rules(THEME) if where == "" and selector == ":root"
             for name, value in values.items()}
    assert (phone["--dw-text-label"], phone["--dw-text-heading"], phone["--dw-card"], phone["--dw-bg"]) == ("12px", "15px", "#24222c", "#000")
    #? the pressing list a desktop list: the card's colour, Explorer's selection
    assert desk["--dw-popover"] == "var(--dw-card)" and desk["--dw-selected-row"] == "var(--dw-selection-bg)"


def test_the_frame_as_the_board_draws_it():
    desk = media_tokens(DESKTOP, DESK)
    assert (desk["--app-desk-side"], desk["--app-desk-bar"], desk["--app-desk-panel"]) == ("232px", "72px", "470px")
    shell = declarations(DESKTOP, ".app-desk.app-shell", DESK)
    assert shell["padding"] == "0 0 var(--app-desk-bar) var(--app-desk-side)"
    assert declarations(DESKTOP, ".app-desk.app-shell.has-side", DESK)["padding-right"] == "var(--app-desk-panel)"
    side = declarations(DESKTOP, ".app-desk .app-side", DESK)
    assert (side["position"], side["width"], side["bottom"], side["background"]) == ("fixed", "var(--app-desk-side)", "var(--app-desk-bar)", "var(--dw-sidebar)")
    bar = declarations(DESKTOP, ".app-desk .app-playbar", DESK)
    assert (bar["position"], bar["height"], bar["bottom"], bar["background"]) == ("fixed", "var(--app-desk-bar)", "0", "var(--dw-player-bar)")
    #? keyboard focus scrolls clear of the bar
    assert declarations(DESKTOP, "html", DESK)["scroll-padding-bottom"] == "var(--app-desk-bar)"
    #? the bar's two sides have the board's 320px from 1280
    assert media_tokens(DESKTOP, COLUMN)["--app-desk-bar-side"] == "320px"


def test_a_side_panel_lies_beside_the_page_never_over_the_bar_and_without_a_backdrop():
    panel = declarations(DESKTOP, ".app-desk .app-layer.is-panel", DESK)
    assert panel["inset"] == "0 0 var(--app-desk-bar) auto" and panel["width"] == "var(--app-desk-panel)"
    assert declarations(DESKTOP, ".app-desk .app-layer.is-panel .app-backdrop", DESK)["display"] == "none"
    #? a third column appears in place - the page making room - and a drawer slides over the page's edge
    assert declarations(DESKTOP, ".app-desk .app-layer.is-column", DESK)["transition"] == "none"
    box = declarations(DESKTOP, ".app-desk .app-layer.is-panel .app-sources", DESK)
    assert (box["transform"], box["background"], box["border-radius"]) == ("translateX(100%)", "var(--dw-side-panel)", "0")
    assert declarations(DESKTOP, ".app-desk .app-layer.is-panel.is-open .app-info", DESK)["transform"] == "none"


def test_six_covers_across():
    assert media_tokens(DESKTOP, DESK)["--app-desk-columns"] == "6"
    for selector in (".app-desk .pl-grid", ".app-desk .app-shelf"):
        assert declarations(DESKTOP, selector, DESK)["grid-template-columns"] == "repeat(var(--app-desk-columns), minmax(0, 1fr))", selector
    #? the shelf no longer scrolls sideways
    assert declarations(DESKTOP, ".app-desk .app-shelf", DESK)["overflow"] == "visible"


def test_the_bars_scrubber_has_its_clocks_at_its_ends():
    scrubber = declarations(DESKTOP, ".app-desk .app-playbar .pl-scrubber", DESK)
    assert scrubber["display"] == "grid" and scrubber["grid-template-columns"] == "auto minmax(0, 1fr) auto"
    assert declarations(DESKTOP, ".app-desk .app-playbar .pl-clocks", DESK)["display"] == "contents"
    assert declarations(DESKTOP, ".app-desk .app-playbar .pl-clocks > :first-child", DESK)["grid-column"] == "1"
    assert declarations(DESKTOP, ".app-desk .app-playbar .pl-scrub", DESK)["grid-column"] == "2"
    assert declarations(DESKTOP, ".app-desk .app-playbar .pl-clocks > :last-child", DESK)["grid-column"] == "3"
    #? the board's thin sunken bar
    assert media_tokens(DESKTOP, DESK)["--pl-scrub-track"] == "6px"


def test_get_pressed_while_the_panel_shows_its_sources_is_tinted_not_solid():
    pressed = declarations(DESKTOP, '.app-desk .app-rg-get[aria-pressed="true"]', DESK)
    assert (pressed["background"], pressed["border-color"], pressed["color"]) == ("var(--dw-toggled-bg)", "var(--dw-toggled-border)", "var(--dw-accent-text)")


def test_the_tracklists_against_column_and_a_sources_five_facts():
    assert media_tokens(DESKTOP, DESK)["--app-desk-against"] == "190px"
    assert "var(--app-desk-against)" in declarations(DESKTOP, ".app-desk .app-rg-table.has-against thead th:nth-child(3)", DESK)["width"]
    card = declarations(DESKTOP, ".app-desk .app-layer.is-panel .app-source", DESK)
    assert card["display"] == "grid" and card["grid-template-columns"] == "var(--app-desk-facts)"
    assert media_tokens(DESKTOP, DESK)["--app-desk-facts"] == "1.4fr 0.85fr 1.25fr 0.75fr 0.55fr"
    speed = declarations(DESKTOP, ".app-desk .app-layer.is-panel .app-source-speed", DESK)
    assert (speed["grid-row"], speed["grid-column"]) == ("2", "1")
    assert declarations(DESKTOP, ".app-desk .app-layer.is-panel .app-source-facts", DESK)["display"] == "contents"


def test_the_sidebar_field_is_never_small_enough_for_ios_to_zoom_under_a_finger():
    assert declarations(DESKTOP, ".app-desk .app-side-input", COARSE)["font-size"] == "var(--dw-text-body)"
    #? a pointer you aim gets the board's 13px
    assert media_tokens(DESKTOP, DESK)["--app-desk-field-text"] == "13px"


def test_the_selection_is_explorers():
    current = declarations(DESKTOP, ".app-desk .app-side-item.is-current", DESK)
    assert (current["background"], current["border-color"], current["color"]) == ("var(--dw-selection-bg)", "var(--dw-selection-border)", "var(--dw-selected-text)")


def class_names(source: str) -> set[str]:
    """Every `app-` class a component's markup names, in a class="..." or class={`...`}."""
    found: set[str] = set()
    for attribute in re.findall(r'class=(?:"([^"]*)"|\{`([^`]*)`\})', source):
        found.update(re.findall(r"\bapp-[a-z0-9-]+", " ".join(attribute)))
    return found


def styled(css: str) -> set[str]:
    return {name for _where, selector, _values in rules(css) for name in re.findall(r"\.(app-[a-z0-9-]+)", selector)}


def test_the_desktops_own_parts_have_class_names_of_their_own():
    """The player bar and the sidebar are drawn only in the desktop frame, styled only here under
    `.app-desk` - so a class of theirs that another component draws, or app.css styles, is restyled by
    their rules wherever it is. `.app-bar` was the bar's name and a job's progress track's: every
    Arriving card and Requests row had its bar fixed across the foot of the screen, and the phone's
    track rule gave the player bar a sunken border."""
    #? the bar's box (a section) and the sidebar's (a nav) are among them, whatever they are called
    roots = {re.search(rf'<{tag} class="(app-[a-z-]+)"', (SRC / name).read_text()).group(1)
             for name, tag in (("player/PlayerBar.tsx", "section"), ("app/Sidebar.tsx", "nav"))}
    own = (class_names((SRC / "player" / "PlayerBar.tsx").read_text()) | class_names((SRC / "app" / "Sidebar.tsx").read_text())) & styled(DESKTOP)
    assert roots <= own, (roots, own)
    elsewhere = set()
    for path in SRC.rglob("*.tsx"):
        if path.name not in ("PlayerBar.tsx", "Sidebar.tsx"):
            elsewhere |= class_names(path.read_text())
    assert own & elsewhere == set()
    assert own & styled(APP) == set()


def test_every_target_is_a_fingers_where_the_pointer_is_coarse():
    """An iPad on its side gets the desktop frame (1024px wide and more): the board's mouse-sized
    targets - a 16px scrubber 6px under a 22px Previous - are Apple's 44px there, and the bar holds the
    transport over the scrubber without the one lying over the other."""
    coarse = media_tokens(DESKTOP, COARSE)
    for token in ("--app-desk-scrub-hit", "--app-desk-play", "--app-desk-tool", "--app-desk-item", "--app-desk-row",
                  "--app-desk-control", "--app-desk-close", "--app-desk-chip-h", "--app-desk-source-get"):
        assert coarse[token] == "var(--pl-hit)", token
    transport = declarations(DESKTOP, ".app-desk .app-playbar-transport .app-playbar-button", COARSE)
    assert (transport["min-width"], transport["min-height"]) == ("var(--pl-hit)", "var(--pl-hit)")
    #? the bar: the transport's 44px, the gap, the scrubber's 44px - and clear of the home indicator
    hit = int(re.search(r"--pl-hit: (\d+)px", (REPO / "interface" / "player" / "player.css").read_text()).group(1))
    rows = int(re.match(r"(\d+)px", coarse["--app-desk-bar-rows"]).group(1))
    assert int(re.match(r"(\d+)px", coarse["--app-desk-bar-touch"]).group(1)) >= 2 * hit + rows
    assert coarse["--app-desk-bar"] == "calc(var(--app-desk-bar-touch) + var(--pl-safe-bottom))"
    assert declarations(DESKTOP, ".app-desk .app-playbar", COARSE)["padding-bottom"] == "var(--pl-safe-bottom)"
    #? a pointer you aim keeps the board's sizes
    desk = media_tokens(DESKTOP, DESK)
    assert (desk["--app-desk-scrub-hit"], desk["--app-desk-bar"]) == ("16px", "72px")


def test_the_against_columns_note_is_text_an_ellipsis_shortens():
    """The chip is a box; the note after it is plain text. As a box of its own (inline-flex) a note too
    long for the 190px column was hidden whole behind the ellipsis - "Other version …" - losing the
    usual length it is there to give."""
    assert declarations(DESKTOP, ".app-desk .app-rg-against .app-rg-chip", DESK)["display"] == "inline-flex"
    assert declarations(DESKTOP, ".app-desk .app-rg-against .app-rg-note", DESK)["display"] == "inline"


def test_the_pressing_is_never_wider_than_its_row():
    """A flex item is as wide as its whole label unless told otherwise, so the pressing's ellipsis never
    came and a long label ran on under the Sources panel."""
    picker = declarations(DESKTOP, ".app-desk .app-picker", DESK)
    assert (picker["min-width"], picker["max-width"]) == ("0", "100%")


def test_a_sources_facts_never_run_into_each_other():
    """The phone's `min-width: 0` let a column shrink under its words - "FLAC 16-24/44.1-96" over the
    size, "12 ahead" out of the card. Each column is at least its longest word, and a value wraps."""
    assert declarations(DESKTOP, ".app-desk .app-layer.is-panel .app-source-fact", DESK)["min-width"] == "auto"
    value = declarations(DESKTOP, ".app-desk .app-layer.is-panel .app-source-value", DESK)
    assert (value["white-space"], value["overflow-wrap"]) == ("normal", "break-word")


def test_beside_a_third_column_the_grids_keep_a_covers_size():
    """Six columns in what a 470px panel leaves were 66px covers at 1280. Beside it, as many as fit at
    the phone grid's 150px, and never more than six (Arriving's cards: three)."""
    desk = media_tokens(DESKTOP, DESK)
    assert (desk["--app-desk-tile-min"], desk["--app-desk-jobs"]) == ("150px", "3")
    for selector in (".app-desk.has-side .pl-grid", ".app-desk.has-side .app-shelf"):
        columns = " ".join(declarations(DESKTOP, selector, DESK)["grid-template-columns"].split())
        assert columns.startswith("repeat(auto-fill, minmax(max(var(--app-desk-tile-min),"), selector
        assert "/ var(--app-desk-columns)" in columns, selector
    jobs = " ".join(declarations(DESKTOP, ".app-desk.has-side .app-arriving .app-jobs", DESK)["grid-template-columns"].split())
    assert jobs.startswith("repeat(auto-fill, minmax(max(var(--app-desk-job-min),") and "/ var(--app-desk-jobs)" in jobs


def test_the_album_you_dont_have_keeps_get_and_the_pressing_clear_of_a_drawer():
    """A drawer (1024-1279px) covers the page from 322px in at 1024, and beside the cover Get starts at
    236px, the pressing past the drawer's edge. So until 1280 they sit under the cover, keeping to the
    part a drawer leaves in view while one is open; from 1280 (a column the page makes room for) back
    beside the cover, as the board draws them."""
    hero = declarations(DESKTOP, ".app-desk .app-rg .pl-album-hero", DESK)
    assert hero["display"] == "grid" and hero["padding-left"] == "var(--pl-edge-left)"
    assert declarations(DESKTOP, ".app-desk .app-rg .pl-hero-cover", DESK)["grid-row"] == "1 / 5"
    assert declarations(DESKTOP, ".app-desk .app-rg .app-rg-actions", DESK)["grid-column"] == "1 / -1"
    assert declarations(DESKTOP, ".app-desk.has-drawer .app-rg .app-rg-actions", DESK)["max-width"] == \
        "calc(100% - var(--app-desk-panel) + var(--pl-edge-right) - var(--app-desk-gap))"
    assert declarations(DESKTOP, ".app-desk.has-drawer .app-rg .app-picker-popover", DESK)["width"] == "auto"
    assert declarations(DESKTOP, ".app-desk .app-rg .app-rg-actions", COLUMN)["grid-column"] == "2"
    assert declarations(DESKTOP, ".app-desk .app-rg .pl-hero-cover", COLUMN)["grid-row"] == "1 / -1"


def test_a_panels_box_takes_focus_without_a_ring():
    for selector in (".app-desk .app-layer.is-panel .app-sources:focus", ".app-desk .app-layer.is-panel .app-info:focus"):
        assert declarations(DESKTOP, selector, DESK)["outline"] == "none", selector


def test_the_visualizer_is_the_whole_screen_over_everything():
    layer = declarations(DESKTOP, ".app-desk .app-viz", DESK)
    assert (layer["position"], layer["inset"], layer["overflow"], layer["background"]) == ("fixed", "0", "hidden", "var(--dw-viz-bg)")
    desk = media_tokens(DESKTOP, DESK)
    assert layer["z-index"] == "var(--app-z-viz)"
    #? over the pin notice (40), the highest thing the app draws, and so over Now Playing's sheets and a panel
    assert int(desk["--app-z-viz"]) > int(tokens(APP)["--app-z-notice"])
    assert declarations(DESKTOP, ".app-desk .app-viz:focus", DESK)["outline"] == "none"
    canvas = declarations(DESKTOP, ".app-desk .app-viz-canvas", DESK)
    assert (canvas["position"], canvas["inset"], canvas["width"], canvas["height"]) == ("absolute", "0", "100%", "100%")
    #? the 2D canvas or the WebGL one, by the attribute - a display rule of its own must not undo it
    assert declarations(DESKTOP, ".app-desk .app-viz-canvas[hidden]", DESK)["display"] == "none"
    #? the board's own colours
    theme = tokens(THEME)
    assert (theme["--dw-viz-bg"], theme["--dw-viz-well"], theme["--dw-viz-artist"]) == ("#050408", "rgba(13, 12, 18, 0.74)", "#c9c9d6")


def test_the_visualizers_controls_fade_together_and_take_the_pointer_only_where_there_is_one():
    chrome = declarations(DESKTOP, ".app-desk .app-viz-chrome", DESK)
    assert (chrome["pointer-events"], chrome["opacity"]) == ("none", "var(--app-viz-shown)")
    assert chrome["transition"] == "opacity var(--app-viz-fade) var(--ease-out)"
    #? about half a second, built on section 7's duration so reduced motion collapses it
    assert media_tokens(DESKTOP, DESK)["--app-viz-fade"] == "calc(var(--duration-slow) * 1.8)"
    assert declarations(DESKTOP, ".app-desk .app-viz.is-still .app-viz-chrome", DESK)["opacity"] == "var(--app-viz-hidden)"
    assert (media_tokens(DESKTOP, DESK)["--app-viz-shown"], media_tokens(DESKTOP, DESK)["--app-viz-hidden"]) == ("1", "0")
    assert declarations(DESKTOP, ".app-desk .app-viz [data-chrome]", DESK)["pointer-events"] == "auto"
    assert declarations(DESKTOP, ".app-desk .app-viz.is-still [data-chrome]", DESK)["pointer-events"] == "none"
    assert declarations(DESKTOP, ".app-desk .app-viz.is-still", DESK)["cursor"] == "none"
    #? the scrims the board draws behind the controls
    assert declarations(DESKTOP, ".app-desk .app-viz-scrim.is-top", DESK)["background"] == "var(--dw-viz-scrim-top)"
    assert declarations(DESKTOP, ".app-desk .app-viz-scrim.is-bottom", DESK)["background"] == "var(--dw-viz-scrim-bottom)"


def test_the_visualizers_choices_wrap_at_a_narrow_desktop_and_the_readout_waits_for_1280():
    top = declarations(DESKTOP, ".app-desk .app-viz-top", DESK)
    assert (top["display"], top["justify-content"], top["left"], top["right"]) == ("flex", "space-between", "var(--app-viz-edge)", "var(--app-viz-edge)")
    #? the song takes only what the choices leave (its basis 0, growing into the rest) and never goes
    #? under its minimum: a long title is cut short, while the choices - their own size - keep one row
    #? wherever that minimum leaves them room. Shrinking both in proportion (`0 1 auto` on each) let a
    #? long title wrap the choices at 1280px and over, and "feel:" then drew over Leave full screen.
    song = declarations(DESKTOP, ".app-desk .app-viz-song", DESK)
    assert (song["flex"], song["min-width"]) == ("1 1 0", "var(--app-viz-song-min)")
    assert declarations(DESKTOP, ".app-desk .app-viz-tools", DESK)["flex"] == "0 1 auto"
    #? ...and from 1280px that is always so: the edges, the gap, the song's minimum and the widest the
    #? choices get (Ambient, "Style: Rotate all": about 833px at the board's sizes) fit
    desk = media_tokens(DESKTOP, DESK)
    px = lambda token: int(re.match(r"(\d+)px", desk[token]).group(1))
    assert constant("COLUMN_MIN") - 2 * px("--app-viz-edge") - px("--app-viz-top-gap") - px("--app-viz-song-min") >= 850
    assert declarations(DESKTOP, ".app-desk .app-viz-title", DESK)["text-overflow"] == "ellipsis"
    tools = declarations(DESKTOP, ".app-desk .app-viz-tools", DESK)
    assert (tools["flex-wrap"], tools["justify-content"]) == ("wrap", "flex-end")
    assert declarations(DESKTOP, ".app-desk .app-viz-readout", DESK)["display"] == "none"
    assert declarations(DESKTOP, ".app-desk .app-viz-readout", COLUMN)["display"] == "flex"
    #? the segmented pickers and the style list as the board draws them
    assert declarations(DESKTOP, ".app-desk .app-viz-segment.is-on", DESK)["background"] == "var(--dw-toggled-bg)"
    assert declarations(DESKTOP, ".app-desk .app-viz-option.is-on", DESK)["background"] == "var(--dw-selection-bg)"
    assert media_tokens(DESKTOP, DESK)["--app-viz-list"] == "190px"
    play = declarations(DESKTOP, ".app-desk .app-viz-play", DESK)
    assert (play["background"], play["width"], play["height"]) == ("var(--dw-primary-bg)", "var(--app-viz-play-w)", "var(--app-viz-play-h)")


def test_a_note_at_the_visualizers_foot_keeps_to_its_corner():
    """Why a song can't be seen is deadwax's own words after the dash, and can run long (a FLAC it
    couldn't repackage, with the reason): kept to the right of play/pause, it wraps in its corner rather
    than running across the foot over the keys at the left or under the button."""
    notes = declarations(DESKTOP, ".app-desk .app-viz-notes", DESK)
    assert notes["right"] == "var(--app-viz-edge)"
    assert notes["max-width"] == "calc(50% - var(--app-viz-edge) - var(--app-viz-play-w) / 2 - var(--app-viz-gap))"
    assert notes["text-align"] == "right"
    assert "white-space" not in declarations(DESKTOP, ".app-desk .app-viz-note", DESK)
    #? the keys at the left, on the same line, are on the other side of the middle
    assert declarations(DESKTOP, ".app-desk .app-viz-hint", DESK)["left"] == "var(--app-viz-edge)"


def test_the_visualizers_controls_are_a_fingers_where_the_pointer_is_coarse():
    """An iPad on its side draws the visualizer (its button is in the bar, 44px there): its own controls
    are 44px too - the pickers' segments (a well that much taller round them), Style and Leave full
    screen, the style list's options, play/pause - and the readout and the list hang under the taller
    button, not over it."""
    coarse = media_tokens(DESKTOP, COARSE)
    for token in ("--app-viz-control", "--app-viz-option", "--app-viz-play-h"):
        assert coarse[token] == "var(--pl-hit)", token
    assert coarse["--app-viz-well"] == "calc(var(--pl-hit) + 2 * (var(--app-viz-well-pad) + var(--dw-hairline)))"
    assert declarations(DESKTOP, ".app-desk .app-viz-segmented", DESK)["height"] == "var(--app-viz-well)"
    assert declarations(DESKTOP, ".app-desk .app-viz-button", DESK)["height"] == "var(--app-viz-control)"
    assert declarations(DESKTOP, ".app-desk .app-viz-option", DESK)["height"] == "var(--app-viz-option)"
    hit = int(re.search(r"--pl-hit: (\d+)px", (REPO / "interface" / "player" / "player.css").read_text()).group(1))
    number = lambda value: int(re.match(r"(\d+)px", value).group(1))
    desk = media_tokens(DESKTOP, DESK)
    #? what hangs under the button keeps the board's distance from its foot
    for token in ("--app-viz-readout-drop", "--app-viz-list-drop"):
        assert number(coarse[token]) - hit == number(desk[token]) - number(desk["--app-viz-control"]), token
    assert number(coarse["--app-viz-play-w"]) >= hit
    #? and the coarse block comes after the visualizer's own, so it wins
    assert DESKTOP.rindex("@media (min-width: 1024px) and (pointer: coarse)") > DESKTOP.index("--app-viz-control: 32px")
    #? a pointer you aim keeps the board's sizes
    assert (desk["--app-viz-control"], desk["--app-viz-option"], desk["--app-viz-play-h"]) == ("32px", "30px", "40px")


def test_the_edit_panel_is_a_side_panel_by_the_same_rule():
    """Beside the page as Sources and Info are: a box sliding over the page's edge as a drawer, there in
    place as a column, focusable by a click with no ring - and a column of its head, tabs and body, the
    body the one part that scrolls (saying its touches pan: the layer takes every touch)."""
    box = declarations(DESKTOP, ".app-desk .app-layer.is-panel .app-edit", DESK)
    assert (box["inset"], box["transform"], box["background"], box["border-radius"]) == ("0", "translateX(100%)", "var(--dw-side-panel)", "0")
    assert declarations(DESKTOP, ".app-desk .app-layer.is-panel.is-open .app-edit", DESK)["transform"] == "none"
    assert declarations(DESKTOP, ".app-desk .app-layer.is-column .app-edit", DESK)["transition"] == "none"
    assert declarations(DESKTOP, ".app-desk .app-layer.is-panel .app-edit:focus", DESK)["outline"] == "none"
    own = declarations(DESKTOP, ".app-desk .app-edit", DESK)
    assert (own["position"], own["display"], own["flex-direction"]) == ("absolute", "flex", "column")
    body = declarations(DESKTOP, ".app-desk .app-edit-body", DESK)
    assert (body["min-height"], body["overflow-x"], body["overflow-y"], body["touch-action"]) == ("0", "hidden", "auto", "pan-y")


def test_the_edit_panels_tabs_are_the_boards_underline_tabs():
    tokens = media_tokens(DESKTOP, DESK)
    assert (tokens["--app-desk-edit-tab-y"], tokens["--app-desk-edit-tab-x"], tokens["--app-desk-edit-rule"]) == ("8px", "10px", "2px")
    assert declarations(DESKTOP, ".app-desk .app-edit-tabs", DESK)["border-bottom"] == "var(--dw-hairline) solid var(--dw-border)"
    tab = declarations(DESKTOP, ".app-desk .app-edit-tab", DESK)
    assert (tab["border-bottom"], tab["color"]) == ("var(--app-desk-edit-rule) solid transparent", "var(--dw-text-2)")
    on = declarations(DESKTOP, ".app-desk .app-edit-tab.is-on", DESK)
    assert (on["border-bottom-color"], on["color"], on["font-weight"]) == ("var(--dw-accent)", "var(--dw-text)", "var(--dw-weight-semibold)")
    #? Edit on the album page: the toggled tint while the panel shows its album, as the board draws it
    pressed = declarations(DESKTOP, '.app-desk .app-edit-toggle[aria-pressed="true"]', DESK)
    assert (pressed["background"], pressed["border-color"], pressed["color"]) == ("var(--dw-toggled-bg)", "var(--dw-toggled-border)", "var(--dw-accent-text)")


def test_the_main_pages_editors_are_styled_by_their_own_ids_inside_the_panel():
    """They are the main page's components, reused as they are - and its main.css isn't on this page - so
    each is drawn here, keyed on its own ids, inside the panel only."""
    selectors = {part.strip() for _where, found, _values in rules(DESKTOP) for part in found.split(",")}
    for key in ("#metadata-window", "#metadata-footer", "#tags-window", "#delete-window", "#art-viewer",
                "#metadata-apply-button", "#tags-apply-button", "#delete-confirm-button"):
        assert any(selector.startswith(".app-desk .app-edit ") and key in selector for selector in selectors), key
    #? the panel's close button stands for the editor's own
    assert declarations(DESKTOP, ".app-desk .app-edit #metadata-close-button", DESK)["display"] == "none"
    #? Apply the solid purple at the board's 36px; delete the one red button, from theme.css section 10
    apply = declarations(DESKTOP, ".app-desk .app-edit #metadata-apply-button", DESK)
    assert (apply["background"], apply["border"], apply["min-height"]) == (
        "var(--dw-primary-bg)", "var(--dw-hairline) solid var(--dw-primary-border)", "var(--app-desk-edit-apply)")
    assert media_tokens(DESKTOP, DESK)["--app-desk-edit-apply"] == "36px"
    danger = declarations(DESKTOP, ".app-desk .app-edit #delete-confirm-button", DESK)
    assert (danger["background"], danger["border"]) == ("var(--dw-danger-bg)", "var(--dw-hairline) solid var(--dw-danger-border)")
    theme = {name for where, selector, values in rules(THEME) if where == "" and selector == ":root" for name in values}
    assert {"--dw-danger-bg", "--dw-danger-border"} <= theme
    #? the folder - the one string people copy - can be selected
    assert declarations(DESKTOP, ".app-desk .app-edit .metadata-path", DESK)["user-select"] == "text"


def test_the_cover_viewer_covers_the_window_over_the_panel():
    """Drawn inside the panel (beside the editor's window, as the main page draws it): fixed is the
    window's, the panel's box having no transform once open, and it sits over the panel's own parts."""
    viewer = declarations(DESKTOP, ".app-desk .app-edit #art-viewer", DESK)
    assert (viewer["position"], viewer["inset"], viewer["z-index"]) == ("fixed", "0", "var(--app-z-edit-viewer)")
    assert declarations(DESKTOP, ".app-desk .app-layer.is-panel.is-open .app-edit", DESK)["transform"] == "none"
    #? zoomed and moved by the viewer's own transform, clipped by its stage, the drag the image's
    assert declarations(DESKTOP, ".app-desk .app-edit .art-viewer-stage", DESK)["overflow"] == "hidden"
    assert declarations(DESKTOP, ".app-desk .app-edit .art-viewer-stage > img", DESK)["touch-action"] == "none"


def test_the_pressings_scroll_inside_the_panel_and_apply_stays_in_reach():
    releases = declarations(DESKTOP, ".app-desk .app-edit .metadata-releases", DESK)
    assert (releases["max-height"], releases["overflow-y"]) == ("var(--app-desk-edit-list)", "auto")
    footer = declarations(DESKTOP, ".app-desk .app-edit #metadata-footer", DESK)
    assert (footer["position"], footer["bottom"], footer["background"]) == ("sticky", "0", "var(--dw-side-panel)")
    assert declarations(DESKTOP, ".app-desk .app-edit .tags-footer", DESK)["position"] == "sticky"


def test_the_edit_panel_is_a_fingers_where_the_pointer_is_coarse():
    coarse = media_tokens(DESKTOP, COARSE)
    assert coarse["--app-desk-edit-control"] == coarse["--app-desk-edit-apply"] == "var(--pl-hit)"
    assert declarations(DESKTOP, ".app-desk .app-edit-tab", COARSE)["min-height"] == "var(--pl-hit)"
    for field in (".app-desk .app-edit .releases-filter-input", ".app-desk .app-edit-select"):
        assert declarations(DESKTOP, field, COARSE)["font-size"] == "var(--dw-text-body)", field
    #? the cover viewer's hint for a hand that taps and pinches
    assert declarations(DESKTOP, ".app-desk .app-edit .hint-touch", COARSE)["display"] == "inline"
    assert declarations(DESKTOP, ".app-desk .app-edit .hint-pointer", COARSE)["display"] == "none"


def test_the_album_page_keeps_play_shuffle_and_edit_clear_of_a_drawer():
    """(review) Beside the cover the album page's buttons start 236px in, and a drawer covers the page from
    322px in at 1024 - so the Edit panel's own drawer opened over Edit, the button that closes it. With a
    drawer open they go under the cover at the main area's edge, wrapping in the part left in view, as the
    album you don't have's Get does; from 1280 (no drawer) nothing moves."""
    page = ".app-desk.has-drawer .pl-album-page:not(.app-rg)"
    hero = declarations(DESKTOP, f"{page} .pl-album-hero", DESK)
    assert (hero["display"], hero["padding-left"]) == ("grid", "var(--pl-edge-left)")
    cover = declarations(DESKTOP, f"{page} .pl-hero-cover", DESK)
    assert (cover["position"], cover["grid-row"]) == ("static", "1 / 6")
    assert declarations(DESKTOP, f"{page} .app-album-chips", DESK)["grid-row"] == "5"
    actions = declarations(DESKTOP, f"{page} .pl-hero-actions", DESK)
    assert (actions["grid-column"], actions["grid-row"], actions["flex-wrap"]) == ("1 / -1", "6", "wrap")
    #? the same reach as the album you don't have's: the hero's width less the drawer's reach into it
    assert actions["max-width"] == declarations(DESKTOP, ".app-desk.has-drawer .app-rg .app-rg-actions", DESK)["max-width"]
    assert not any(selector.startswith(".app-desk.has-drawer .pl-album-page") for where, selector, _values in rules(DESKTOP) if where != DESK)


def test_the_release_editors_preview_breaks_a_long_tag_name_inside_its_column():
    """(review) The preview names each tag by its key - musicbrainz_releasegroupid is 146px at 11px, with
    no break in it - in an 84px column: it ran over the old value beside it."""
    assert declarations(DESKTOP, ".app-desk .app-edit .metadata-change", DESK)["grid-template-columns"].startswith("var(--app-desk-edit-tag)")
    tag = declarations(DESKTOP, ".app-desk .app-edit .metadata-tag", DESK)
    assert (tag["min-width"], tag["overflow-wrap"]) == ("0", "anywhere")


def test_busy_words_in_a_solid_button_are_the_buttons_white():
    """(review) A busy label is the muted grey beside a button - and inside Apply ("Applying, renaming in
    20s"), the tag editor's Apply, the viewer's Save and "delete permanently" that was grey on purple or
    red, about 1.5:1."""
    for button in ("#metadata-apply-button", "#tags-apply-button", "#delete-confirm-button", ".win-button.is-default"):
        assert declarations(DESKTOP, f".app-desk .app-edit {button} .loading-blocks", DESK)["color"] == "inherit", button
        assert declarations(DESKTOP, f".app-desk .app-edit {button}", DESK)["color"] == "var(--dw-text)", button


def test_a_pressing_has_its_track_count_on_its_first_line():
    """(review) The detail takes a line of its own; drawn before the count, it pushed the count onto a third."""
    detail = declarations(DESKTOP, ".app-desk .app-edit .metadata-release-detail", DESK)
    count = declarations(DESKTOP, ".app-desk .app-edit .metadata-release-tracks", DESK)
    assert detail["flex-basis"] == "100%"
    assert int(count["order"]) < int(detail["order"])
    assert declarations(DESKTOP, ".app-desk .app-edit .metadata-release", DESK)["flex-wrap"] == "wrap"


def test_long_names_in_the_panel_are_broken_never_clipped():
    """(review) The body clips sideways, so a rip log's name in the delete warning, a stranger's filename as
    a title in the tag editor's list, or a path in the panel's own words ran past its edge, cut mid-word."""
    assert declarations(DESKTOP, ".app-desk .app-edit-body", DESK)["overflow-x"] == "hidden"
    for selector in (".app-desk .app-edit-note", ".app-desk .app-edit .delete-others", ".app-desk .app-edit .tags-track-list > li > span:last-child"):
        assert declarations(DESKTOP, selector, DESK)["overflow-wrap"] == "anywhere", selector
    assert declarations(DESKTOP, ".app-desk .app-edit .tags-track-list > li > span:last-child", DESK)["min-width"] == "0"


def test_a_tick_box_is_a_fingers_target_where_the_pointer_is_coarse():
    """(review) The box is 16px; its label fills the cell, and is 44px where the pointer is coarse - with
    the panel's other small targets."""
    assert media_tokens(DESKTOP, DESK)["--app-desk-edit-tick"] == "var(--app-desk-edit-check)"
    assert media_tokens(DESKTOP, COARSE)["--app-desk-edit-tick"] == "var(--pl-hit)"
    hit = declarations(DESKTOP, ".app-desk .app-edit-hit", DESK)
    assert (hit["min-width"], hit["min-height"], hit["display"]) == ("var(--app-desk-edit-tick)", "var(--app-desk-edit-tick)", "flex")
    assert declarations(DESKTOP, ".app-desk .app-edit-tracks .app-edit-tick", DESK)["width"] == \
        "calc(var(--app-desk-edit-tick) + 2 * var(--app-desk-cell-gap))"
    for selector in (".app-desk .app-edit-choice", ".app-desk .app-edit .tags-tracks > summary", ".app-desk .app-edit .tags-revert",
                     ".app-desk .app-edit .metadata-issue-undo", ".app-desk .app-edit-link"):
        assert declarations(DESKTOP, selector, COARSE)["min-height"] == "var(--pl-hit)", selector
    #? and the box sits in its label in the markup
    panel = (SRC / "app" / "EditPanel.tsx").read_text()
    assert len(re.findall(r'<label class="app-edit-hit">\s*<input\s+type="checkbox"', panel)) == 2


# ---------------------------------------------------------------- Needs a look (2.0.0-player.25)

def test_the_queue_rows_are_the_frames_rows_and_a_fingers_where_the_pointer_is_coarse():
    """A row at the frame's row height (44px itself where the pointer is coarse), a button filling its
    line, with the folder's cover inside it; a facet a finger's target where the pointer is coarse."""
    row = declarations(DESKTOP, ".app-desk .app-queue-row", DESK)
    assert (row["min-height"], row["width"], row["text-align"]) == ("var(--app-desk-row)", "100%", "left")
    assert media_tokens(DESKTOP, COARSE)["--app-desk-row"] == "var(--pl-hit)"
    assert declarations(DESKTOP, ".app-desk .app-queue-row", COARSE)["min-height"] == "var(--pl-hit)"
    assert declarations(DESKTOP, ".app-desk .app-queue-facet", COARSE)["min-height"] == "var(--pl-hit)"
    cover = declarations(DESKTOP, ".app-desk .app-queue-cover", DESK)
    assert (cover["width"], cover["height"], cover["flex"]) == ("var(--app-desk-queue-cover)",) * 2 + ("none",)
    assert media_tokens(DESKTOP, DESK)["--app-desk-queue-cover"] == "28px"


def test_the_queue_rows_chips_give_way_before_the_albums_name():
    """The tree row's lesson: the chips shrink a thousand times faster than the name, to nothing, and are
    never cut to a stub - those that don't fit wrap out of their one line; the name ellipsizes last."""
    chips = declarations(DESKTOP, ".app-desk .app-queue-chips", DESK)
    assert chips["flex"] == "0 var(--app-desk-queue-give) auto"
    assert media_tokens(DESKTOP, DESK)["--app-desk-queue-give"] == "1000"
    assert (chips["min-width"], chips["overflow"], chips["flex-wrap"], chips["height"]) == ("0", "hidden", "wrap", "var(--app-desk-queue-chip)")
    chip = declarations(DESKTOP, ".app-desk .app-queue-chip", DESK)
    assert (chip["flex"], chip["max-width"], chip["text-overflow"], chip["white-space"]) == ("none", "100%", "ellipsis", "nowrap")
    text = declarations(DESKTOP, ".app-desk .app-queue-text", DESK)
    assert text["flex"] == "1 1 auto" and text["min-width"].startswith("min(var(--app-desk-queue-text-min)")
    for selector in (".app-desk .app-queue-album", ".app-desk .app-queue-artist"):
        assert declarations(DESKTOP, selector, DESK)["text-overflow"] == "ellipsis", selector


def test_the_row_the_panel_has_open_is_explorers_selection_and_a_dealt_with_row_is_faded_but_not_its_word():
    current = declarations(DESKTOP, ".app-desk .app-queue-row.is-current", DESK)
    assert (current["border-color"], current["background"]) == ("var(--dw-selection-border)", "var(--dw-selection-bg)")
    faded = declarations(DESKTOP, ".app-desk .app-queue-row.is-done .app-queue-text", DESK)
    assert faded == declarations(DESKTOP, ".app-desk .app-queue-row.is-done .app-queue-cover", DESK) == {"opacity": "var(--app-desk-queue-done)"}
    assert not any(".app-queue-mark" in selector and "opacity" in values for _where, selector, values in rules(DESKTOP))


def test_a_held_row_is_seen_to_refuse_a_tap_and_the_page_body_takes_focus_without_a_ring():
    """2.0.0-player.25 review: while a session's rows are held for the fresh scan they are aria-disabled
    - faded and a progress cursor, no hover - so a click visibly does nothing; the page's body takes
    focus (a Try again that worked) with no ring of its own."""
    held = declarations(DESKTOP, ".app-desk .app-queue-row[aria-disabled='true']", DESK)
    assert (held["opacity"], held["cursor"]) == ("var(--app-job-busy)", "progress")
    assert declarations(DESKTOP, ".app-desk .app-queue-row[aria-disabled='true']:hover", DESK)["background"] == "transparent"
    assert declarations(DESKTOP, ".app-desk .app-queue-body:focus", DESK)["outline"] == "none"


def test_the_checking_line_is_always_a_row_tall_and_the_list_keeps_clear_of_a_drawer():
    """"Checking the library…" lives in a line that is always there and a row tall, so its going moves no
    row; a drawer open over the page (1024-1279px) keeps the list to the part left in view."""
    assert declarations(DESKTOP, ".app-desk .app-queue-checking", DESK)["min-height"] == "var(--app-desk-row)"
    assert declarations(DESKTOP, ".app-desk.has-drawer .app-queue-body", DESK)["max-width"] == \
        "calc(100% - var(--app-desk-panel) + var(--pl-edge-right) - var(--app-desk-gap))"
    page = (SRC / "app" / "NeedsALook.tsx").read_text()
    assert '<p class="app-queue-checking" role="status">' in page


def test_the_queue_page_has_no_solid_purple_button():
    """STYLE.md: one solid purple button a screen - Apply, in the panel beside it."""
    page = (SRC / "app" / "NeedsALook.tsx").read_text()
    assert "is-primary" not in page and "app-primary" not in page
    for _where, selector, values in rules(DESKTOP):
        if "app-queue" in selector:
            assert "var(--dw-accent)" not in values.get("background", ""), selector


def test_the_settings_save_bar_sits_above_the_player_bar_and_save_is_its_one_solid_purple_button():
    """2.0.0-player.33: the save bar at the foot of the page area - sticky above the player bar, whatever
    height a coarse pointer gives it - and Save the page's one primary."""
    bar = declarations(DESKTOP, ".app-desk .app-settings-savebar", DESK)
    assert (bar["position"], bar["bottom"], bar["min-height"]) == ("sticky", "var(--app-desk-bar)", "var(--app-desk-set-bar)")
    desk, coarse = media_tokens(DESKTOP, DESK), media_tokens(DESKTOP, COARSE)
    assert desk["--app-desk-set-bar"] == "calc(var(--app-desk-control) + 2 * var(--app-desk-set-bar-pad))"
    assert coarse["--app-desk-set-bar"] == "calc(var(--pl-hit) + 2 * var(--app-desk-set-bar-pad))"
    save = declarations(DESKTOP, ".app-desk .app-settings-save", DESK)
    assert (save["background"], save["border-color"]) == ("var(--dw-primary-bg)", "var(--dw-primary-border)")
    page = (SRC / "app" / "ServerSettings.tsx").read_text()
    assert page.count("is-primary") == 1 and 'class="app-button is-primary app-settings-save"' in page
    for _where, selector, values in rules(DESKTOP):
        if ("app-settings" in selector or "app-log" in selector) and "app-settings-save" not in selector:
            assert "--dw-primary-bg" not in values.get("background", ""), selector


def test_the_settings_page_reaches_the_foot_and_its_idle_bar_takes_no_clicks_nor_hides_focus():
    """Sticky only pins while the page is taller than the window: on a short tab the bar would sit under
    the last group, mid-screen. So the page fills the page area at least, the body taking the room. And the
    bar, always there, is a box over what a long tab scrolls under it: idle (transparent) it takes no
    clicks, and saying something (opaque) it covers what is there, so keyboard focus stops above it too."""
    page = declarations(DESKTOP, ".app-desk .app-settings:not(.is-phone)", DESK)
    assert (page["display"], page["flex-direction"], page["min-height"]) == ("flex", "column", "var(--app-desk-set-page)")
    assert media_tokens(DESKTOP, DESK)["--app-desk-set-page"] == "calc(100dvh - var(--app-desk-bar))"
    assert declarations(DESKTOP, ".app-desk .app-settings:not(.is-phone) .app-settings-body", DESK)["flex"] == "1 0 auto"
    assert declarations(DESKTOP, ".app-desk .app-settings-savebar:not(.is-said)", DESK)["pointer-events"] == "none"
    assert "pointer-events" not in declarations(DESKTOP, ".app-desk .app-settings-savebar.is-said", DESK)
    assert declarations(DESKTOP, "html:has(.app-desk .app-pane:not([hidden]) .app-settings-savebar.is-said)", DESK)["scroll-padding-bottom"] == \
        "calc(var(--app-desk-bar) + var(--app-desk-set-bar) + var(--dw-hairline))"
    #? only for the pane that shows (review): the page stays drawn in You's hidden pane while another tab
    #? shows, holding "Saved." or a draft, and :has() matches what is hidden - every other tab's focus
    #? stopped a save bar's height higher than its player bar needs
    for _where, selector, values in rules(DESKTOP):
        if "scroll-padding" in " ".join(values) and "app-settings-savebar" in selector:
            assert ".app-pane:not([hidden]) .app-settings-savebar" in selector, selector
    panes = (SRC / "app" / "App.tsx").read_text()
    assert 'class="app-pane" data-tab={tab} hidden={nav.tab !== tab}' in panes
    #? and the words focus is given as Save and Discard go draw no ring
    assert declarations(DESKTOP, ".app-desk .app-settings-savebar-text:focus", DESK)["outline"] == "none"


def test_the_settings_rows_are_the_tabs_own_classes_styled_here_and_long_values_break():
    """The main page's settings rows, by their own names under .app-settings - and a key, a path in a
    note, a reason, the verdict: broken, never run out of the page."""
    for selector in (".app-desk .app-settings .settings-env-key", ".app-desk .app-settings .settings-env-effect",
                     ".app-desk .app-settings .settings-env-detail", ".app-desk .app-settings .settings-verdict",
                     ".app-desk .app-settings-savebar-text", ".app-desk .app-log-words"):
        assert declarations(DESKTOP, selector, DESK)["overflow-wrap"] == "anywhere", selector
    field = declarations(DESKTOP, ".app-desk .app-settings .settings-env-input", DESK)
    assert (field["background"], field["min-width"]) == ("var(--dw-well)", "0")
    assert declarations(DESKTOP, ".app-desk .app-settings .settings-env.is-edited", DESK)["border-left-color"] == "var(--dw-amber-icon)"


def test_where_the_pointer_is_coarse_the_settings_fields_are_17px_and_the_controls_a_finger():
    field = declarations(DESKTOP, ".app-desk .app-settings .settings-env-input", COARSE)
    assert (field["font-size"], field["height"]) == ("var(--dw-text-body)", "var(--pl-hit)")
    for selector in (".app-desk .app-settings .settings-env-revert", ".app-desk .app-settings-save",
                     ".app-desk .app-settings-discard", ".app-desk .app-log-clear"):
        assert declarations(DESKTOP, selector, COARSE)["min-height"] == "var(--pl-hit)", selector


def test_the_log_draws_errors_red_and_warnings_amber_and_both_pages_keep_clear_of_a_drawer():
    assert declarations(DESKTOP, ".app-desk .app-log-row.is-error .app-log-words", DESK)["color"] == "var(--dw-danger-text)"
    assert declarations(DESKTOP, ".app-desk .app-log-row.is-warning .app-log-words", DESK)["color"] == "var(--dw-amber-text)"
    row = declarations(DESKTOP, ".app-desk .app-log-row", DESK)
    assert row["font-size"] == "var(--dw-text-data)"
    for selector in (".app-desk.has-drawer .app-settings-body", ".app-desk.has-drawer .app-log-body", ".app-desk.has-drawer .app-settings-savebar"):
        assert declarations(DESKTOP, selector, DESK)["max-width"] == \
            "calc(100% - var(--app-desk-panel) + var(--pl-edge-right) - var(--app-desk-gap))", selector
