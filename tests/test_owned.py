"""
What's already in the library, for the search view.

Asked for: "a way to see which editions are already in my library when I'm searching for new
ones". The search marks a release group, and each pressing of it, you hold - which needs to know
WHICH album and edition every folder is, cheaply. These pin the two halves of "cheaply": the
saved scan answers when nothing has changed, and anything that has changed the library makes
the next answer come from the disk.
"""

import asyncio
from types import SimpleNamespace

import pytest

import src.library as library
from src.config import Config
from src.library import (library_is_behind, note_library_changed, read_album_dir, scan_library,
                         forget_cached_album)
from tests.test_retag import seed

ALBUM = "Tame Impala/The Slow Rush (2020)"


def run(coro):
    return asyncio.run(coro)


def request():
    return SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace()))


@pytest.fixture(autouse=True)
def clean_cache(monkeypatch):
    library.clear_scan_cache()
    yield
    library.clear_scan_cache()


def test_the_scan_says_which_album_as_well_as_which_pressing(tmp_path):
    directory = seed(tmp_path, musicbrainz_albumid="rel-1", musicbrainz_releasegroupid="rg-1")
    album = read_album_dir(directory, tmp_path)
    assert (album["release_mbid"], album["release_group_mbid"]) == ("rel-1", "rg-1")


def test_an_untagged_album_has_no_group_rather_than_a_guessed_one(tmp_path):
    directory = seed(tmp_path)
    assert read_album_dir(directory, tmp_path)["release_group_mbid"] == ""


def test_a_full_walk_catches_the_cache_up_and_anything_that_changes_the_library_puts_it_behind(tmp_path):
    directory = seed(tmp_path)
    note_library_changed()
    assert library_is_behind()

    scan_library(str(tmp_path))
    assert not library_is_behind()

    forget_cached_album(str(directory))
    assert library_is_behind()


def owned(monkeypatch, tmp_path):
    from src.routes import library as routes
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    return run(routes.owned(request()))


def test_owned_carries_only_what_says_which_album_and_edition(tmp_path, monkeypatch):
    seed(tmp_path, musicbrainz_albumid="rel-1", musicbrainz_releasegroupid="rg-1")
    note_library_changed()

    answer = owned(monkeypatch, tmp_path)

    assert answer["problem"] is None
    assert answer["albums"] == [{
        "path": ALBUM, "artist": "Tame Impala", "album": "The Slow Rush", "year": "2020",
        "edition": "", "release_mbid": "rel-1", "release_group_mbid": "rg-1",
        "formats": ["flac"], "track_count": 2,
    }]


def test_owned_answers_from_the_saved_scan_when_nothing_has_changed(tmp_path, monkeypatch):
    seed(tmp_path, musicbrainz_albumid="rel-1")
    scan_library(str(tmp_path))
    walks = []
    monkeypatch.setattr(library, "_walk", lambda *a: walks.append(a) or ([], 0))
    from src.routes import library as routes
    monkeypatch.setattr(routes, "scan_library", lambda *a: walks.append(a) or {})

    answer = owned(monkeypatch, tmp_path)

    assert walks == []
    assert answer["stale"] is True
    assert [a["release_mbid"] for a in answer["albums"]] == ["rel-1"]


def test_an_album_the_poller_just_filed_is_found_by_the_next_search(tmp_path, monkeypatch):
    """The saved scan can't know about it - the next answer must come from the disk."""
    seed(tmp_path, musicbrainz_albumid="rel-1")
    scan_library(str(tmp_path))
    seed(tmp_path, artist="Portishead", folder="Dummy (1994)", album="Dummy", musicbrainz_albumid="dummy")
    note_library_changed()

    answer = owned(monkeypatch, tmp_path)

    assert answer["stale"] is False
    assert sorted(a["release_mbid"] for a in answer["albums"]) == ["dummy", "rel-1"]


def test_no_library_is_said_rather_than_raised(monkeypatch):
    from src.routes import library as routes
    monkeypatch.setattr(Config, "LIBRARY_PATH", "")
    assert run(routes.owned(request()))["problem"] == "LIBRARY_PATH is not set"


def test_filing_an_album_marks_the_library_changed(tmp_path, monkeypatch):
    from src import poller
    scan_library(str(tmp_path))
    assert not library_is_behind()

    class Store:
        async def update_status(self, *a): pass
        async def record_albums_seen(self, *a, **k): pass

    async def organized(*a, **k):
        return {"organized": 2, "failed": 0, "skipped": 0, "plan": {"album_dir": str(tmp_path / ALBUM)}}

    monkeypatch.setattr(poller, "organize_job", organized)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "FETCH_LYRICS", "off")
    monkeypatch.setattr(Config, "organizing_enabled", classmethod(lambda cls: True))

    run(poller._organize_if_enabled({"id": 1, "artist": "a", "album": "b"}, Store()))

    assert library_is_behind()
