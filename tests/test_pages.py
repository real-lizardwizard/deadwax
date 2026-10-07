"""
The hand-written pages and what they load (2.0.0-player.9), through the real app, start().

A page's script is an unhashed bundle named after a vite entry, and nothing else joins the two: a
page naming a script the build doesn't make is a blank page with nothing on screen to say why. So
each page's `/dist/<name>.js` must be a vite input whose source exists, and each stylesheet it
links (and each one those import) must be served. The app grows in place at /player/, where James's
home-screen app is scoped: the manifest's start_url and scope must stay there, or iOS stops
treating the installed icon as that app. And the app's own stylesheets are revalidated and gzipped,
like the page around it - since 2.0.0-player.19 the desktop frame's too, linked last. And since
2.0.0-player.36 the turntable's test bench at /player/lab/, a page of its own, built in a pass of its own
so the app's bundle is what it would be without it - its page stamped as the app's is.
"""

import json
import os
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
    #? the turntable's test bench (2.0.0-player.36)
    "/player/lab/": INTERFACE / "player" / "lab" / "index.html",
}


@pytest.fixture(scope="module")
def client():
    return TestClient(start())  # no `with`: no lifespan, nothing connects


def vite_inputs() -> dict[str, str]:
    """The build's named entries, as vite.config.ts lists them - the app's pass and the test bench's
    (2.0.0-player.36: APP_INPUTS and LAB_INPUTS) - name -> source path under ui/."""
    config = (UI / "vite.config.ts").read_text()
    blocks = re.findall(r"_INPUTS\s*=\s*\{(.*?)\}", config, re.S)
    assert blocks, "vite.config.ts names no entries (APP_INPUTS, LAB_INPUTS)"
    found: dict[str, str] = {}
    for block in blocks:
        found.update(dict(re.findall(r"'([\w-]+)':\s*'([^']+)'", block)))
    return found


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
    assert inputs.keys() >= {"deadwax-ui", "deadwax-player", "deadwax-lab"}
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
               INTERFACE / "player" / "lab" / "index.html", *INTERFACE.glob("player/lab/*.css"),
               INTERFACE / "styles" / "theme.css", INTERFACE / "styles" / "main.css"]
    for path in shipped:
        text = path.read_text()
        assert "fonts.googleapis.com" not in text and "fonts.gstatic.com" not in text, path


# ---- loading: what the app's page names is kept for good; the page itself is always asked for ----

def test_the_app_page_names_each_stylesheet_and_script_with_that_files_own_stamp(client):
    """Until this the installed app re-asked about every stylesheet and script on every launch
    (no-cache: a round trip each to be told nothing changed). The page stamps each with the file's
    size and time of writing, so a file that changed is another address."""
    response = client.get("/player/")
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-cache"
    assert response.headers["content-type"].startswith("text/html")

    named = re.findall(r'(?:href|src)="(/(?:player|dist|styles)/[^"?]+\.(?:css|js)(?:\?[^"]*)?)"', response.text)
    assert [n.split("?")[0] for n in named] == [
        "/styles/theme.css", "/player/player.css", "/player/app.css", "/player/app-desktop.css", "/dist/deadwax-player.js"]
    for address in named:
        path, _, query = address.partition("?")
        file = INTERFACE / path.lstrip("/")
        if not file.exists():  # the bundle, in a checkout that hasn't been built
            assert query == ""
            continue
        found = file.stat()
        assert query == f"v={found.st_mtime_ns:x}-{found.st_size:x}"
    #? the manifest and the icons keep their plain addresses: the home-screen app is scoped by them
    assert 'href="/player/manifest.json"' in response.text
    assert client.get("/player/index.html").text == response.text


def test_a_stamped_file_is_kept_for_good_and_a_plain_one_still_asked_about(client):
    stamped = client.get("/player/app.css?v=abc-123", headers={"Accept-Encoding": "gzip"})
    assert stamped.status_code == 200
    assert stamped.headers["cache-control"] == "public, max-age=31536000, immutable"
    assert stamped.headers.get("content-encoding") == "gzip"
    assert client.get("/player/app.css").headers["cache-control"] == "no-cache"
    #? the old page's files take no stamp from anything, and a query alone makes nothing else immutable
    assert client.get("/deadwax/me?v=1").headers.get("cache-control") != "public, max-age=31536000, immutable"


def test_a_file_written_again_gets_another_address(client):
    sheet = INTERFACE / "player" / "app.css"
    before = re.search(r'/player/app\.css\?v=([0-9a-f-]+)', client.get("/player/").text)[1]
    found = sheet.stat()
    os.utime(sheet, ns=(found.st_atime_ns, found.st_mtime_ns + 1_000_000_000))
    try:
        after = re.search(r'/player/app\.css\?v=([0-9a-f-]+)', client.get("/player/").text)[1]
    finally:
        os.utime(sheet, ns=(found.st_atime_ns, found.st_mtime_ns))
    assert after != before


def test_the_font_is_kept_for_good_and_the_icons_for_a_day(client):
    font = client.get("/styles/font/noto-sans/noto-sans-latin.woff2")
    assert font.status_code == 200
    assert font.headers["cache-control"] == "public, max-age=31536000, immutable"
    assert client.get("/player/icon-192.png").headers["cache-control"] == "public, max-age=86400"
    assert client.get("/player/icon.svg").headers["cache-control"] == "public, max-age=86400"
    #? the manifest is the app's scope and name: still asked about
    assert client.get("/player/manifest.json").headers["cache-control"] == "no-cache"
