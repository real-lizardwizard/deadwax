"""
The Cover Art Archive client: what it asks for, and who it says is asking.

Two things changed together and both are pinned here. The size is a setting now - `full` fetches
the original upload rather than the 500px thumbnail that used to be the only choice - and the
user agent is built from the contact and the running version rather than typed by hand.

Driven through httpx's MockTransport, so these exercise the real client with no network.
"""

import asyncio

import httpx
import pytest

from src import __version__
from src.api.coverart_endpoint import BASE_URL, CoverArtClient, cover_art_path
from src.config import Config

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 4096


def jpeg(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, headers={"content-type": "image/jpeg"}, content=JPEG)


def fetch(handler, size=None):
    """fetch_front against a fake Archive. Returns the art and every request it made."""
    seen: list[httpx.Request] = []

    def record(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)

    async def go():
        client = CoverArtClient()
        client.client = httpx.AsyncClient(base_url=BASE_URL, transport=httpx.MockTransport(record))
        try:
            return await client.fetch_front("mb-1", size)
        finally:
            await client.close_client()

    return asyncio.run(go()), seen


# ---------------------------------------------------------------- sizes

@pytest.mark.parametrize("size, path", [
    ("250", "/release/mb-1/front-250"),
    ("500", "/release/mb-1/front-500"),
    ("1200", "/release/mb-1/front-1200"),
    #? the bare front redirects to the original upload
    ("full", "/release/mb-1/front"),
])
def test_each_size_asks_for_the_matching_image(size, path):
    assert cover_art_path("mb-1", size) == path


def test_an_unrecognised_size_asks_for_the_default():
    """The value can come from a database row edited by hand, and front-huge could only 404."""
    assert cover_art_path("mb-1", "huge") == "/release/mb-1/front-500"


def test_500_is_still_what_you_get_unless_you_choose_otherwise(monkeypatch):
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "500")

    _, seen = fetch(jpeg)

    assert seen[0].url.path == "/release/mb-1/front-500"


def test_the_configured_size_is_what_gets_fetched(monkeypatch):
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "full")

    art, seen = fetch(jpeg)

    assert art == (JPEG, "image/jpeg")
    assert [request.url.path for request in seen] == ["/release/mb-1/front"]


def test_an_original_that_is_not_an_image_falls_back_to_1200(monkeypatch):
    """The Archive takes PDFs, and a release's front can be one. Its thumbnails are always JPEGs."""
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "full")

    def pdf_first(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/front"):
            return httpx.Response(200, headers={"content-type": "application/pdf"},
                                  content=b"%PDF" + b"\x00" * 4096)
        return jpeg(request)

    art, seen = fetch(pdf_first)

    assert art == (JPEG, "image/jpeg")
    assert [request.url.path for request in seen] == ["/release/mb-1/front", "/release/mb-1/front-1200"]


def test_a_release_with_no_cover_is_not_asked_again_at_another_size(monkeypatch):
    """A 404 is a fact about the release. Asking for a smaller copy of nothing is still nothing."""
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "full")

    art, seen = fetch(lambda request: httpx.Response(404))

    assert art is None
    assert len(seen) == 1


# ---------------------------------------------------------------- who is asking

def test_the_archive_is_told_who_is_asking_and_which_version(monkeypatch):
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "me@example.com")

    _, seen = fetch(jpeg)

    assert seen[0].headers["user-agent"] == f"deadwax/{__version__} ( me@example.com )"


def test_a_contact_changed_in_the_settings_tab_is_sent_without_a_restart(monkeypatch):
    """The client lives as long as the process, so the header is set per request, not per client."""
    agents: list[str] = []

    def record(request: httpx.Request) -> httpx.Response:
        agents.append(request.headers["user-agent"])
        return jpeg(request)

    async def go():
        client = CoverArtClient()
        client.client = httpx.AsyncClient(base_url=BASE_URL, transport=httpx.MockTransport(record))
        monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "old@example.com")
        await client.fetch_front("mb-1")
        monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "new@example.com")
        await client.fetch_front("mb-1")
        await client.close_client()

    asyncio.run(go())

    assert "old@example.com" in agents[0]
    assert "new@example.com" in agents[1]
