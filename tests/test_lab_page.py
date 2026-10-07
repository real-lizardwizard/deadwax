"""
The turntable's test bench at /player/lab/ (2.0.0-player.36), through the real app, start().

A page of its own beside the app: its script the `deadwax-lab` entry, built in a pass of its own after the
app's (so rollup never splits what it shares with the player into chunks the app's page then loads); its
page served as the app's is - asked for every time, what it names stamped and kept for good; no part of
the installed app (not in the manifest, no manifest of its own); its stylesheet tokens only, as app.css;
and nothing about it on the server but its files.
"""

import json
import re
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from src.api.app import start
from tests.test_app_css import LOOK_PROPERTIES, RAW_LENGTH, rules
from tests.test_pages import scripts, stylesheets

REPO = Path(__file__).resolve().parent.parent
INTERFACE = REPO / "interface"
UI = REPO / "ui"
PAGE = INTERFACE / "player" / "lab" / "index.html"
LAB_CSS = INTERFACE / "player" / "lab" / "lab.css"


@pytest.fixture(scope="module")
def client():
    return TestClient(start())  # no `with`: no lifespan, nothing connects


def test_the_bench_page_loads_its_own_entry_and_it_renders_the_bench():
    assert scripts(PAGE) == ["/dist/deadwax-lab.js"]
    main = (UI / "src" / "lab" / "main.tsx").read_text()
    assert "from './Bench'" in main and "render(<Bench />" in main
    assert 'id="lab-root"' in PAGE.read_text()


def test_the_bench_is_built_in_a_pass_of_its_own_after_the_apps():
    package = json.loads((UI / "package.json").read_text())
    build = package["scripts"]["build"]
    assert build == "tsc --noEmit && vite build && vite build --mode lab"
    config = (UI / "vite.config.ts").read_text()
    #? the bench's pass builds its entry alone, and adds to the folder the app's pass emptied
    assert "input: mode === 'lab' ? LAB_INPUTS : APP_INPUTS" in config
    assert "emptyOutDir: mode !== 'lab'" in config
    assert re.search(r"const LAB_INPUTS = \{\s*'deadwax-lab': 'src/lab/main.tsx',\s*\}", config)
    assert "deadwax-lab" not in re.search(r"const APP_INPUTS = \{(.*?)\}", config, re.S).group(1)


def test_the_bench_links_the_turntables_stylesheets_and_its_own_last():
    sheets = stylesheets(PAGE)
    assert sheets == ["/styles/theme.css", "/player/player.css", "/player/app.css", "/player/lab/lab.css"]
    page = PAGE.read_text()
    assert 'viewport-fit=cover' in page and '<meta charset="UTF-8">' in page


def test_the_bench_is_no_part_of_the_installed_app(client):
    page = PAGE.read_text()
    assert 'rel="manifest"' not in page
    manifest = client.get("/player/manifest.json").json()
    assert "lab" not in json.dumps(manifest)


@pytest.mark.parametrize("address", ["/player/lab/", "/player/lab/index.html"])
def test_the_bench_page_is_asked_for_every_time_and_what_it_names_is_stamped(client, address):
    response = client.get(address)
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-cache"
    assert response.headers["content-type"].startswith("text/html")
    named = re.findall(r'(?:href|src)="(/(?:player|dist|styles)/[^"?]+\.(?:css|js)(?:\?[^"]*)?)"', response.text)
    assert [n.split("?")[0] for n in named] == [
        "/styles/theme.css", "/player/player.css", "/player/app.css", "/player/lab/lab.css", "/dist/deadwax-lab.js"]
    for address_named in named:
        path, _, query = address_named.partition("?")
        file = INTERFACE / path.lstrip("/")
        if not file.exists():  # the bundle, in a checkout that hasn't been built
            assert query == ""
            continue
        found = file.stat()
        assert query == f"v={found.st_mtime_ns:x}-{found.st_size:x}"


def test_the_benchs_stylesheet_is_kept_when_stamped_and_gzipped(client):
    stamped = client.get("/player/lab/lab.css?v=abc-1", headers={"Accept-Encoding": "gzip"})
    assert stamped.status_code == 200
    assert stamped.headers["cache-control"] == "public, max-age=31536000, immutable"
    assert stamped.headers.get("content-encoding") == "gzip"
    assert client.get("/player/lab/lab.css").headers["cache-control"] == "no-cache"


def test_the_benchs_stylesheet_draws_only_from_tokens():
    raw = []
    for _context, selector, values in rules(LAB_CSS.read_text()):
        if selector == ":root":
            continue  # its few tokens
        for name, value in values.items():
            if name.startswith("--"):
                raw.append((selector, name, "a token defined outside :root"))
            elif RAW_LENGTH.search(value):
                raw.append((selector, name, value))
            elif name in LOOK_PROPERTIES and not value.startswith("var(") and value not in ("inherit", "normal"):
                raw.append((selector, name, value))
    assert raw == []


def test_every_control_on_the_bench_is_a_fingers_height_where_the_pointer_is_coarse():
    css = LAB_CSS.read_text()
    coarse = {" ".join(selector.split()): values for context, selector, values in rules(css) if context == "@media (pointer: coarse)"}
    assert coarse[":root"]["--lab-control"] == "var(--pl-hit)"
    assert coarse[".lab-option"]["min-height"] == "var(--pl-hit)"
    #? every control's height reads --lab-control, so the coarse pointer reaches all of them
    flat = {" ".join(selector.split()): values for context, selector, values in rules(css) if context == ""}
    for selector in (".lab-option", ".lab-check", ".lab-file input, .lab-field select, .lab-field input"):
        assert flat[selector]["min-height"] == "var(--lab-control)", selector
    #? the app's own buttons are a tap target tall already (app.css: --dw-row, 44px)
    assert "min-height: var(--dw-row)" in (INTERFACE / "player" / "app.css").read_text()


def test_the_benchs_text_fields_are_never_small_enough_to_zoom():
    flat = {" ".join(selector.split()): values for context, selector, values in rules(LAB_CSS.read_text()) if context == ""}
    assert flat[".lab-file input, .lab-field select, .lab-field input"]["font-size"] == "var(--dw-text-body)"


def test_every_focusable_control_of_the_benchs_own_draws_a_ring():
    flat = {" ".join(selector.split()): values for context, selector, values in rules(LAB_CSS.read_text()) if context == ""}
    ring = flat[".lab-option input:focus-visible, .lab-check input:focus-visible, .lab-file input:focus-visible, .lab-field select:focus-visible, .lab-field input:focus-visible"]
    assert ring["outline"] == "var(--app-ring) solid var(--dw-accent)"


def test_nothing_about_the_bench_on_the_server_but_its_page():
    app = (REPO / "src" / "api" / "app.py").read_text()
    #? its two routes serve its page; no route of the bench's own beyond them
    assert app.count('stamped_page("player/lab/index.html")') == 2
    assert "lab" not in "".join(re.findall(r"include_router\([^)]*\)", app))


def test_a_status_line_holds_its_line_whether_or_not_it_says_anything():
    #? review of 2.0.0-player.36: min-height read a bare line-height token (1.45, no unit), which a length
    #? can't be - so it reserved nothing, and the motions moved down a line under the finger as it spoke
    css = LAB_CSS.read_text()
    root = {name: value for context, selector, values in rules(css) if context == "" and selector == ":root" for name, value in values.items()}
    assert root["--lab-status-line"] == "calc(var(--dw-text-footnote) * var(--dw-leading-note))"
    flat = {" ".join(selector.split()): values for context, selector, values in rules(css) if context == ""}
    assert flat[".lab-status"]["min-height"] == "var(--lab-status-line)"
    #? and nothing in the stylesheet takes a line-height token for a length
    lengths = ("height", "min-height", "max-height", "width", "min-width", "max-width", "margin", "padding", "gap", "top", "bottom", "left", "right")
    bare = [(selector, name, value) for _c, selector, values in rules(css) for name, value in values.items()
            if (name in lengths or name.startswith(("margin-", "padding-"))) and re.fullmatch(r"var\(--dw-leading-[\w-]+\)", value.strip())]
    assert bare == []


def test_the_benchs_record_carries_a_mark_that_turns_with_it():
    #? the bench's record has no cover: a plain label on round grooves looks the same at every angle, so
    #? its turning - 33 1/3, a coast, a hand matching the song's speed - couldn't be seen
    css = LAB_CSS.read_text()
    root = {name: value for context, selector, values in rules(css) if context == "" and selector == ":root" for name, value in values.items()}
    assert root["--lab-label-mark"].startswith("conic-gradient(")
    flat = {" ".join(selector.split()): values for context, selector, values in rules(css) if context == ""}
    assert flat[".lab-deck .app-tt-label"]["background-image"] == "var(--lab-label-mark)"
    #? the label is drawn inside the face the deck turns (Turntable.tsx), and only the bench's is marked
    turntable = (UI / "src" / "player" / "Turntable.tsx").read_text()
    assert re.search(r"class=\{`app-tt-face[^`]*`\}>\s*<Cover [^>]*class=\"app-tt-label\"", turntable)
    assert "lab-label-mark" not in (INTERFACE / "player" / "app.css").read_text()


def test_a_control_that_cant_be_used_just_now_is_faded_and_keeps_its_focus():
    flat = {" ".join(selector.split()): values for context, selector, values in rules(LAB_CSS.read_text()) if context == ""}
    assert flat['.lab .app-button[aria-disabled="true"]']["opacity"] == "var(--app-pin-off)"
    bench = (UI / "src" / "lab" / "Bench.tsx").read_text()
    #? no button of the bench's own is `disabled` - it would drop a keyboard's focus to the page
    assert re.findall(r"<button[^>]*\sdisabled=", bench) == []


def test_a_motions_turn_of_the_record_is_kept_where_turntable_never_writes():
    #? review of 2.0.0-player.36: "Turn it for me" wrote its turn into the transform Turntable writes for a
    #? hand's turn - and the next hand's turn wrote over it, the record jumping back by the motion's whole
    #? turn. It is a property on the bench's own box now, which lab.css turns the record by with the
    #? individual `rotate` - added to Turntable's transform on the same element, never in place of it
    css = LAB_CSS.read_text()
    root = {name: value for context, selector, values in rules(css) if context == "" and selector == ":root" for name, value in values.items()}
    assert root["--lab-motion-turn"] == "0deg"
    flat = {" ".join(selector.split()): values for context, selector, values in rules(css) if context == ""}
    assert flat[".lab-deck .app-tt-turn"] == {"rotate": "var(--lab-motion-turn)"}
    bench = (UI / "src" / "lab" / "Bench.tsx").read_text()
    assert "deckBox.current?.style.setProperty('--lab-motion-turn'" in bench
    assert ".style.transform" not in bench and "app-tt-turn" not in bench
    #? the bench's box has no style a render would put back, and the element turned is Turntable's turn,
    #? whose transform is the hand's
    assert re.search(r'<div ref=\{deckBox\} class="lab-deck" inert=\{busy\}>', bench)
    turntable = (UI / "src" / "player" / "Turntable.tsx").read_text()
    assert re.search(r'<span class="app-tt-turn" style=\{\{ transform: `rotate\(', turntable)
