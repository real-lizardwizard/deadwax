"""
Applying a release writes the tags, waits, and only then renames the folder (v1.0.1).

Navidrome carries every user's plays, ratings, favourites and playlist entries across a folder
rename (same tags) and across a retag (same path) - but not both in one scan, where the old ids
simply go missing with everything on them. A one-step apply was exactly that. So when an apply
changes an id tag AND moves the folder, the route writes the tags, pauses RETAG_RENAME_WAIT
seconds for Navidrome's watcher to see them where the album already is, then renames.
"""

import sys
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient
from mutagen.flac import FLAC

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.config import Config, parse_rename_wait, rename_wait_seconds  # noqa: E402
from src.retag import changes_player_ids, execute_retag, move_retagged, plan_retag  # noqa: E402
from src.routes import library  # noqa: E402
from tests.test_retag import RELEASE, seed  # noqa: E402

ALBUM = "Tame Impala/The Slow Rush (2020)"
RENAMED = "Tame Impala/The Slow Rush (2020) [Deluxe edition]"


# ----- which applies need the pause -----

def test_a_new_release_id_plus_a_rename_needs_the_pause(tmp_path):
    seed(tmp_path)
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path))
    assert plan["moves"] and changes_player_ids(plan)


def test_a_rename_alone_does_not(tmp_path):
    """Same tags, new folder: Navidrome follows it as a move, nothing to wait for."""
    seed(tmp_path, musicbrainz_albumid="mbid-deluxe")
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path))
    assert plan["moves"]
    assert not changes_player_ids(plan)


def test_a_retag_in_place_does_not(tmp_path):
    """New tags, same folder: Navidrome carries everything across on its own."""
    seed(tmp_path, folder="The Slow Rush (2020) [Deluxe edition]")
    plan = plan_retag(RENAMED, RELEASE, str(tmp_path))
    assert not plan["moves"]
    assert not changes_player_ids(plan)


# ----- the two halves -----

def test_the_tags_can_be_written_without_the_rename(tmp_path):
    directory = seed(tmp_path)
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path))

    results = execute_retag(plan, RELEASE, "apply", move=False)
    assert results["tagged"] == 2 and results["moved_to"] is None
    assert directory.is_dir(), "still where it was"
    assert FLAC(str(directory / "01 - One More Year.flac"))["musicbrainz_albumid"] == ["mbid-deluxe"]

    move_retagged(plan, results)
    assert results["moved_to"] == str(tmp_path / RENAMED)
    assert not directory.exists() and (tmp_path / RENAMED).is_dir()


def test_a_failed_tag_write_still_leaves_the_folder_in_place(tmp_path):
    seed(tmp_path)
    plan = plan_retag(ALBUM, RELEASE, str(tmp_path))
    results = {"dry_run": False, "failed": 1, "moved_to": None, "problems": []}
    move_retagged(plan, results)
    assert results["moved_to"] is None
    assert "left the folder in place" in results["problems"][0]


# ----- the route -----

def client(monkeypatch, tmp_path, wait):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", wait)
    app = FastAPI()
    app.include_router(library.router, prefix="/deadwax/library")
    return TestClient(app)


def test_the_route_writes_tags_pauses_then_renames(monkeypatch, tmp_path):
    directory = seed(tmp_path)
    seen = []

    async def pause(seconds):
        #? at the moment of the pause: tags written, folder not yet moved
        tagged = FLAC(str(directory / "01 - One More Year.flac")).get("musicbrainz_albumid")
        seen.append((seconds, tagged, directory.is_dir()))

    monkeypatch.setattr(library.asyncio, "sleep", pause)
    response = client(monkeypatch, tmp_path, "7").post(
        "/deadwax/library/retag/apply", json={"album_path": ALBUM, "release": RELEASE})

    assert response.status_code == 200
    assert seen == [(7, ["mbid-deluxe"], True)]
    assert response.json()["results"]["moved_to"] == str(tmp_path / RENAMED)
    assert response.json()["results"]["rename_wait"] == 7


def test_zero_renames_straight_away(monkeypatch, tmp_path):
    seed(tmp_path)
    monkeypatch.setattr(library.asyncio, "sleep", lambda s: (_ for _ in ()).throw(AssertionError("paused")))
    response = client(monkeypatch, tmp_path, "0").post(
        "/deadwax/library/retag/apply", json={"album_path": ALBUM, "release": RELEASE})

    assert response.status_code == 200
    assert response.json()["results"]["moved_to"] == str(tmp_path / RENAMED)
    assert response.json()["results"]["rename_wait"] == 0


def test_the_preview_says_how_long_it_will_pause(monkeypatch, tmp_path):
    seed(tmp_path)
    plan = client(monkeypatch, tmp_path, "15").post(
        "/deadwax/library/retag/preview", json={"album_path": ALBUM, "release": RELEASE}).json()
    assert plan["rename_wait"] == 15


# ----- the setting -----

def test_the_setting_is_whole_seconds_from_0_to_300(monkeypatch):
    assert [parse_rename_wait(v) for v in ("0", "20", "300", "301", "-1", "2.5", "soon")] == \
        [0, 20, 300, None, None, None, None]
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "garbage")
    assert rename_wait_seconds() == 20, "unreadable falls back to the default"
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "0")
    assert rename_wait_seconds() == 0
