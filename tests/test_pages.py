"""
The hand-written pages and what they load (2.0.0-player.9), through the real app, start().

A page's script is an unhashed bundle named after a vite entry, and nothing else joins the two: a
page naming a script the build doesn't make is a blank page with nothing on screen to say why. So
each page's `/dist/<name>.js` must be a vite input whose source exists, and each stylesheet it
links (and each one those import) must be served. The app grows in place at /player/, where James's
home-screen app is scoped: the manifest's start_url and scope must stay there, or iOS stops
treating the installed icon as that app. And the app's own stylesheets are revalidated and gzipped,
like the page around it - since 2.0.0-player.19 the desktop frame's too, linked last.
"""

import json
import re
from pathlib import Path
from urllib.parse import urljoin

import pytest
from fastapi.testclient import TestClient

from src.api.app import start

REPO = Path(__file__).resolve().parent.parent
INTERFACE = REPO / "interface"
UI = REPO / "ui"

#? each hand-written page, and the address it is served at
PAGES = {
    "/": INTERFACE / "index.html",
    "/player/": INTERFACE / "player" / "index.html",
}


@pytest.fixture(scope="module")
def client():
    return TestClient(start())  # no `with`: no lifespan, nothing connects


def vite_inputs() -> dict[str, str]:
    """The build's named entries, as vite.config.ts lists them: name -> source path under ui/."""
    config = (UI / "vite.config.ts").read_text()
    block = re.search(r"input:\s*\{(.*?)\}", config, re.S)
    assert block, "vite.config.ts has no rollupOptions.input block"
    return dict(re.findall(r"'([\w-]+)':\s*'([^']+)'", block.group(1)))


def _html(page: Path) -> str:
    """The page without its comments - a link or script commented out isn't loaded."""
    return re.sub(r"<!--.*?-->", "", page.read_text(), flags=re.S)


def scripts(page: Path) -> list[str]:
    return re.findall(r'<script\b[^>]*\bsrc="([^"]+)"', _html(page))


def stylesheets(page: Path) -> list[str]:
    """Every stylesheet the page links, in order."""
    found = []
    for tag in re.findall(r"<link\b[^>]*>", _html(page)):
        rel = re.search(r'\brel="([^"]*)"', tag)
        href = re.search(r'\bhref="([^"]*)"', tag)
        if rel and href and "stylesheet" in rel.group(1).split():
            found.append(href.group(1))
    return found


def test_the_build_makes_both_entries_and_their_sources_exist():
    inputs = vite_inputs()
    assert inputs.keys() >= {"deadwax-ui", "deadwax-player"}
    for name, source in inputs.items():
        assert (UI / source).is_file(), f"vite entry {name} names {source}, which isn't there"


@pytest.mark.parametrize("address", PAGES)
def test_each_pages_bundle_is_a_vite_entry(address):
    inputs = vite_inputs()
    bundles = [urljoin(address, src) for src in scripts(PAGES[address]) if "/dist/" in urljoin(address, src)]
    assert bundles, f"{address} loads no bundle from /dist/"
    for bundle in bundles:
        name = re.fullmatch(r"/dist/([\w-]+)\.js", bundle)
        assert name, f"{address} loads {bundle}, which isn't an entry's fixed name"
        assert name.group(1) in inputs, f"{address} loads {bundle}, which no vite entry builds"


def test_the_player_page_loads_the_player_entry_and_it_renders_the_app():
    assert "/dist/deadwax-player.js" in scripts(PAGES["/player/"])
    assert vite_inputs()["deadwax-player"] == "src/player/main.tsx"
    main = (UI / "src" / "player" / "main.tsx").read_text()
    assert "from '../app/App'" in main and "render(<App />" in main


@pytest.mark.parametrize("address", PAGES)
def test_every_linked_stylesheet_and_what_it_imports_is_served(client, address):
    sheets = sorted({urljoin(address, href) for href in stylesheets(PAGES[address])})
    assert sheets, f"{address} links no stylesheet"
    for sheet in sheets:
        response = client.get(sheet)
        assert response.status_code == 200, f"{address} links {sheet}, which answers {response.status_code}"
        for imported in re.findall(r"@import\s+url\(['\"]?([^'\")]+)['\"]?\)", response.text):
            target = urljoin(sheet, imported)
            assert client.get(target).status_code == 200, f"{sheet} imports {target}, which isn't served"


def test_the_player_page_links_its_own_stylesheet_after_the_players():
    sheets = [urljoin("/player/", href) for href in stylesheets(PAGES["/player/"])]
    assert "/player/player.css" in sheets and "/player/app.css" in sheets
    assert sheets.index("/player/player.css") < sheets.index("/player/app.css")


def test_the_desktop_frames_stylesheet_is_linked_last_over_both():
    """2.0.0-player.19: app-desktop.css restyles player.css's and app.css's rules from 1024px, so it
    comes after both - an earlier link would lose every tie it was written to win."""
    sheets = [urljoin("/player/", href) for href in stylesheets(PAGES["/player/"])]
    assert sheets[-1] == "/player/app-desktop.css"
    assert sheets.index("/player/app.css") < sheets.index("/player/app-desktop.css")


def test_the_app_stays_at_player_where_the_home_screen_app_is_scoped(client):
    page = PAGES["/player/"].read_text()
    assert 'rel="manifest" href="/player/manifest.json"' in page
    manifest = client.get("/player/manifest.json").json()
    assert manifest["start_url"] == "/player/"
    assert manifest["scope"] == "/player/"
    assert manifest["display"] == "standalone"
    #? the file on disk too, so a test reading the served copy can't be fooled by a stale cache
    assert json.loads((INTERFACE / "player" / "manifest.json").read_text())["scope"] == "/player/"


@pytest.mark.parametrize("sheet", ["/player/app.css", "/player/app-desktop.css"])
def test_the_apps_stylesheet_is_revalidated_and_gzipped(client, sheet):
    response = client.get(sheet, headers={"Accept-Encoding": "gzip"})

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-cache"
    assert response.headers.get("content-encoding") == "gzip"
    assert response.headers["content-type"].startswith("text/css")


def test_no_page_or_stylesheet_loads_a_font_from_the_internet():
    """The canvas boards link Noto Sans from Google Fonts; deadwax self-hosts it and runs offline."""
    shipped = [INTERFACE / "index.html", INTERFACE / "player" / "index.html", *INTERFACE.glob("player/*.css"),
               INTERFACE / "styles" / "theme.css", INTERFACE / "styles" / "main.css"]
    for path in shipped:
        text = path.read_text()
        assert "fonts.googleapis.com" not in text and "fonts.gstatic.com" not in text, path
