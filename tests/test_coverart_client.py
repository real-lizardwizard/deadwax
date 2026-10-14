"""
The Cover Art Archive client: what it asks for, and who it says is asking.

Two things changed together and both are pinned here. The size is a setting now - `full` fetches
the original upload rather than the 500px thumbnail that used to be the only choice - and the
user agent is built from the contact and the running version rather than typed by hand. And
(2.0.0-player.42) why no cover came back: a release with none is a 404 from /library/art/fetch, an
Archive that couldn't be reached or answered badly a 502 - which a run of Get covers counts apart.

Driven through httpx's MockTransport, so these exercise the real client with no network.
"""

import asyncio
from pathlib import Path

import httpx
import pytest
from fastapi import HTTPException

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


# ---------------------------------------------------------------- none, or no answer (2.0.0-player.42)
#? "the release has no cover" is a fact about the release; "the Archive didn't give one" is worth
#? trying again - and a run of Get covers counts the two apart only if the route says which it was

def why(handler):
    """fetch_front_why against a fake Archive."""
    async def go():
        client = CoverArtClient()
        client.client = httpx.AsyncClient(base_url=BASE_URL, transport=httpx.MockTransport(handler))
        try:
            return await client.fetch_front_why("mb-1")
        finally:
            await client.close_client()

    return asyncio.run(go())


def unreachable(request: httpx.Request) -> httpx.Response:
    raise httpx.ConnectError("the Archive went away", request=request)


def error_page(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, headers={"content-type": "image/jpeg"}, content=b"\xff\xd8 an error page")


@pytest.mark.parametrize("handler, reason", [
    (lambda request: httpx.Response(404), "missing"),
    (unreachable, "unreachable"),
    (lambda request: httpx.Response(503), "failed"),
    (lambda request: httpx.Response(500), "failed"),
    (error_page, "truncated"),
])
def test_why_no_cover_came_back_is_said(handler, reason):
    assert why(handler) == (None, reason)


def test_a_cover_is_ok_and_fetch_front_still_gives_only_the_art():
    assert why(jpeg) == ((JPEG, "image/jpeg"), "ok")
    art, _ = fetch(lambda request: httpx.Response(503))
    assert art is None


def test_no_release_to_ask_about_is_none_to_find():
    assert asyncio.run(CoverArtClient().fetch_front_why("")) == (None, "missing")


@pytest.fixture
def cover_route(tmp_path, monkeypatch):
    from src.routes import library as routes
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "500")
    monkeypatch.setattr(routes, "forget_cached_album", lambda path: None)
    return routes


def get_cover(routes, monkeypatch, handler):
    """POST /library/art/fetch for the seeded album - the plain path a bulk run takes - through the real
    client against a fake Archive."""
    from types import SimpleNamespace

    from tests.test_retag import seed

    async def go():
        client = CoverArtClient()
        client.client = httpx.AsyncClient(base_url=BASE_URL, transport=httpx.MockTransport(handler))
        monkeypatch.setattr(routes, "coverart_client", client)
        try:
            return await routes.fetch_cover_art(SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace())),
                                                routes.CoverArtRequest(album_path="Tame Impala/The Slow Rush (2020)"))
        finally:
            await client.close_client()

    seed(Path(Config.LIBRARY_PATH), musicbrainz_albumid="rel-1")
    return asyncio.run(go())


def test_the_cover_route_saves_the_releases_cover(cover_route, monkeypatch, tmp_path):
    answer = get_cover(cover_route, monkeypatch, jpeg)
    assert answer["written"] == "cover.jpg"
    assert (tmp_path / "Tame Impala" / "The Slow Rush (2020)" / "cover.jpg").read_bytes() == JPEG


def test_the_cover_route_answers_404_only_when_the_release_has_no_cover(cover_route, monkeypatch):
    with pytest.raises(HTTPException) as refused:
        get_cover(cover_route, monkeypatch, lambda request: httpx.Response(404))
    assert (refused.value.status_code, refused.value.detail) == (404, "the Cover Art Archive has no front cover for that release")


@pytest.mark.parametrize("handler, detail", [
    (unreachable, "the Cover Art Archive couldn't be reached - try again"),
    (lambda request: httpx.Response(503), "the cover couldn't be downloaded from the Cover Art Archive - try again"),
    (error_page, "the cover couldn't be downloaded from the Cover Art Archive - try again"),
])
def test_an_archive_that_gave_no_answer_is_a_502_never_none_on_the_archive(cover_route, monkeypatch, tmp_path, handler, detail):
    """Before 2.0.0-player.42 every one of these was a 404 "has no front cover", which a bulk run counted as
    "had none on the Archive" - during one of the Archive's outages, every album of the run."""
    with pytest.raises(HTTPException) as refused:
        get_cover(cover_route, monkeypatch, handler)
    assert (refused.value.status_code, refused.value.detail) == (502, detail)
    assert not (tmp_path / "Tame Impala" / "The Slow Rush (2020)" / "cover.jpg").exists()


# ---------------------------------------------------------------- the 1200px fallback's own answer
#? at COVER_ART_SIZE=full an original that isn't a savable image is asked for again at 1200px, and it is
#? THAT request's answer that says why there's no cover - a release whose 1200px copy is a 404 has none
#? (counted "had none on the Archive"), never "not an image" (counted failed, try again)

def pdf_then(fallback):
    """The original a PDF, the 1200px copy whatever `fallback` answers."""
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/front"):
            return httpx.Response(200, headers={"content-type": "application/pdf"}, content=b"%PDF" + b"\x00" * 4096)
        return fallback(request)

    return handler


@pytest.mark.parametrize("fallback, reason", [
    (lambda request: httpx.Response(404), "missing"),
    (unreachable, "unreachable"),
    (lambda request: httpx.Response(503), "failed"),
])
def test_after_the_1200_fallback_why_is_the_fallbacks_answer(monkeypatch, fallback, reason):
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "full")
    assert why(pdf_then(fallback)) == (None, reason)


def test_after_the_1200_fallback_a_cover_is_ok(monkeypatch):
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "full")
    assert why(pdf_then(jpeg)) == ((JPEG, "image/jpeg"), "ok")


@pytest.mark.parametrize("fallback, status, detail", [
    (lambda request: httpx.Response(404), 404, "the Cover Art Archive has no front cover for that release"),
    (unreachable, 502, "the Cover Art Archive couldn't be reached - try again"),
])
def test_the_cover_route_follows_the_1200_fallbacks_answer(cover_route, monkeypatch, fallback, status, detail):
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "full")
    with pytest.raises(HTTPException) as refused:
        get_cover(cover_route, monkeypatch, pdf_then(fallback))
    assert (refused.value.status_code, refused.value.detail) == (status, detail)
