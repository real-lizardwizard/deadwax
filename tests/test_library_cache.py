"""
The saved library scan, disc numbers, and the track viewer's endpoint.

Real files with real tags throughout, as in test_library.py - the risk in all three is what
actually comes back off a file or out of the database, which is exactly what a mock would hide.
"""

import asyncio
import shutil
import sqlite3

import pytest
from mutagen.flac import FLAC

from src import library
from src.library import (SCAN_FORMAT, drain_cache_changes, forget_cached_album, scan_library,
                         seed_cache, snapshot_library)
from src.organizer import tag_values
from src.retag import execute_retag, plan_retag, read_current_tags
from src.store import JobStore

STREAMINFO = (
    b"fLaC" + b"\x80\x00\x00\x22"
    + b"\x10\x00\x10\x00\x00\x00\x00\x00\x00\x00\x0a\xc4\x42\xf0\x00\x00\x00\x00" + b"\x00" * 16
)


def write_flac(path, **tags):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(STREAMINFO)
    audio = FLAC(str(path))
    for key, value in tags.items():
        audio[key] = str(value)
    audio.save()
    return path


def seed_album(root, artist="Tame Impala", folder="The Slow Rush (2020)", album="The Slow Rush",
               tracks=2):
    directory = root / artist / folder
    for n in range(1, tracks + 1):
        write_flac(directory / f"{n:02d} - Track {n}.flac", album=album, albumartist=artist,
                   artist=artist, title=f"Track {n}", tracknumber=str(n), date="2020")
    return directory


def run(coroutine):
    return asyncio.run(coroutine)


def boom(*_args, **_kwargs):
    raise AssertionError("this should not have touched the disk")


@pytest.fixture(autouse=True)
def fresh_cache():
    """Every module-level cache, emptied - including which root the route thinks it loaded."""
    from src.routes import library as route

    library.clear_scan_cache()
    route._cache_loaded_for = None
    yield
    library.clear_scan_cache()
    route._cache_loaded_for = None


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


# ---------------------------------------------------------------- disc numbers, read

def two_disc_album(root, discnumber=lambda disc: str(disc)):
    """
    Two discs of two tracks, named so that ordering by number alone would interleave them:
    "01 - D1T1", "01 - D2T1", "02 - D1T2", "02 - D2T2".
    """
    directory = root / "Pink Floyd" / "The Wall (1979)"
    for disc in (1, 2):
        for n in (1, 2):
            write_flac(directory / f"{n:02d} - D{disc}T{n}.flac", album="The Wall",
                       albumartist="Pink Floyd", artist="Pink Floyd", title=f"D{disc}T{n}",
                       tracknumber=str(n), discnumber=discnumber(disc), date="1979")
    return directory


def test_a_multi_disc_album_runs_disc_by_disc(tmp_path):
    """Numbering restarts per disc, so ordering on the number alone deals the discs out alternately."""
    two_disc_album(tmp_path)
    [album] = scan_library(str(tmp_path))["albums"]

    assert [t["title"] for t in album["tracks"]] == ["D1T1", "D1T2", "D2T1", "D2T2"]
    assert [t["disc"] for t in album["tracks"]] == [1, 1, 2, 2]
    assert album["disc_count"] == 2


def test_a_disc_written_as_n_of_m_is_read_as_the_disc(tmp_path):
    two_disc_album(tmp_path, discnumber=lambda disc: f"{disc}/2")
    [album] = scan_library(str(tmp_path))["albums"]
    assert [t["disc"] for t in album["tracks"]] == [1, 1, 2, 2]


def test_an_album_with_no_disc_tags_claims_no_discs(tmp_path):
    """0, not a guessed 1 - the viewer only splits by disc when the files actually say so."""
    seed_album(tmp_path)
    [album] = scan_library(str(tmp_path))["albums"]
    assert album["disc_count"] == 0
    assert all(t["disc"] is None for t in album["tracks"])


# ---------------------------------------------------------------- the snapshot

def test_there_is_no_snapshot_before_anything_has_been_scanned(tmp_path):
    seed_album(tmp_path)
    assert snapshot_library(str(tmp_path)) is None


def test_a_snapshot_answers_without_touching_the_disk(tmp_path, monkeypatch):
    seed_album(tmp_path)
    scan_library(str(tmp_path))

    monkeypatch.setattr(library.os, "walk", boom)
    monkeypatch.setattr(library, "read_album_dir", boom)

    result = snapshot_library(str(tmp_path))
    assert result["stale"] is True
    assert result["album_count"] == 1
    assert result["albums"][0]["album"] == "The Slow Rush"


def test_a_real_scan_is_never_marked_stale(tmp_path):
    seed_album(tmp_path)
    assert scan_library(str(tmp_path))["stale"] is False


def test_a_snapshot_holds_only_its_own_librarys_albums(tmp_path):
    seed_album(tmp_path / "one")
    seed_album(tmp_path / "two", artist="Boards of Canada", folder="Geogaddi (2002)", album="Geogaddi")
    scan_library(str(tmp_path / "one"))

    assert snapshot_library(str(tmp_path / "two")) is None
    assert snapshot_library(str(tmp_path / "one"))["album_count"] == 1


def test_decorating_a_response_leaves_the_cache_alone(tmp_path):
    """
    The scan used to hand out the cached dicts themselves, and _mark_multi_edition labels an
    unlabelled edition "Standard" in place. So once its sibling was deleted, the survivor - whose
    own folder hadn't changed, so it came straight from the cache - went on calling itself
    Standard with nothing to be standard beside.
    """
    seed_album(tmp_path)
    deluxe = seed_album(tmp_path, folder="The Slow Rush (2020) [Deluxe]", tracks=3)

    first = scan_library(str(tmp_path))["albums"]
    assert sorted(a["edition"] for a in first) == ["Deluxe", "Standard"]

    shutil.rmtree(deluxe)
    [survivor] = scan_library(str(tmp_path))["albums"]

    assert survivor["edition"] == ""
    assert survivor["edition_count"] == 1


# ---------------------------------------------------------------- what gets saved

def test_the_first_scan_saves_every_album_and_an_unchanged_rescan_saves_none(tmp_path):
    seed_album(tmp_path)
    seed_album(tmp_path, artist="Boards of Canada", folder="Geogaddi (2002)", album="Geogaddi")

    scan_library(str(tmp_path))
    upserts, removals = drain_cache_changes()
    assert len(upserts) == 2 and removals == []

    scan_library(str(tmp_path))
    assert drain_cache_changes() == ([], [])


def test_forgetting_an_album_removes_its_saved_copy_too(tmp_path):
    """Otherwise a restart would load the pre-retag tags straight back against a matching mtime."""
    directory = seed_album(tmp_path)
    scan_library(str(tmp_path))
    drain_cache_changes()

    forget_cached_album(str(directory))

    assert drain_cache_changes() == ([], [str(directory)])


def test_a_folder_that_disappears_is_removed_from_the_saved_copy(tmp_path):
    directory = seed_album(tmp_path)
    scan_library(str(tmp_path))
    drain_cache_changes()

    shutil.rmtree(directory)
    scan_library(str(tmp_path))

    assert drain_cache_changes() == ([], [str(directory)])


def test_a_forced_rescan_resaves_everything(tmp_path):
    seed_album(tmp_path)
    scan_library(str(tmp_path))
    drain_cache_changes()

    scan_library(str(tmp_path), force=True)
    upserts, removals = drain_cache_changes()

    assert len(upserts) == 1
    #? re-read, so it is saved again - not deleted
    assert removals == []


def test_the_saved_scan_survives_a_restart(tmp_path, monkeypatch, store):
    """The point of the whole exercise: after a restart, no tag is re-read for an unchanged folder."""
    root = tmp_path / "library"
    seed_album(root)
    scan_library(str(root))
    upserts, removals = drain_cache_changes()
    assert run(store.save_library_cache(str(root), upserts, removals, SCAN_FORMAT))

    library.clear_scan_cache()  # the restart

    assert seed_cache(run(store.load_library_cache(str(root), SCAN_FORMAT))) == 1

    monkeypatch.setattr(library, "read_album_dir", boom)
    result = scan_library(str(root))
    assert result["album_count"] == 1
    assert result["cached"] == 1


def test_seeding_never_overwrites_what_this_process_already_read(tmp_path):
    directory = seed_album(tmp_path)
    scan_library(str(tmp_path))

    seed_cache([(str(directory), 0.0, {"album": "a stale copy"})])

    assert library._album_cache[str(directory)][1]["album"] == "The Slow Rush"


def test_saved_entries_from_another_scan_format_are_not_loaded(tmp_path, store):
    """An old row would otherwise be served forever for any folder nobody touched since the upgrade."""
    root = tmp_path / "library"
    seed_album(root)
    scan_library(str(root))
    upserts, removals = drain_cache_changes()
    run(store.save_library_cache(str(root), upserts, removals, SCAN_FORMAT - 1))

    assert run(store.load_library_cache(str(root), SCAN_FORMAT)) == []


def test_a_saved_row_that_will_not_parse_is_skipped_rather_than_fatal(tmp_path, store):
    root = tmp_path / "library"
    seed_album(root)
    scan_library(str(root))
    upserts, removals = drain_cache_changes()
    run(store.save_library_cache(str(root), upserts, removals, SCAN_FORMAT))

    with sqlite3.connect(store.path) as connection:
        connection.execute(
            "INSERT INTO library_cache (path, root, mtime, format, album) VALUES (?, ?, ?, ?, ?)",
            (str(root / "broken"), str(root), 1.0, SCAN_FORMAT, "{not json"),
        )

    assert len(run(store.load_library_cache(str(root), SCAN_FORMAT))) == 1


def test_an_unavailable_store_saves_and_loads_nothing_quietly(tmp_path):
    broken = JobStore(str(tmp_path / "state" / "db"))  # never init()ed, so unavailable
    assert run(broken.save_library_cache(str(tmp_path), [], [], SCAN_FORMAT)) is False
    assert run(broken.load_library_cache(str(tmp_path), SCAN_FORMAT)) == []
    assert run(broken.library_scan_info(str(tmp_path))) is None


# ---------------------------------------------------------------- the route

def make_client(root, monkeypatch, store=None):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    from src.config import Config
    from src.routes import library as library_route

    monkeypatch.setattr(Config, "LIBRARY_PATH", str(root))
    app = FastAPI()
    app.state.store = store
    app.include_router(library_route.router, prefix="/deadwax/library")
    return TestClient(app)


def test_asking_for_a_snapshot_with_nothing_cached_gets_a_real_scan(tmp_path, monkeypatch):
    """So the interface never draws an empty library that is merely unscanned."""
    seed_album(tmp_path)
    client = make_client(tmp_path, monkeypatch)

    response = client.get("/deadwax/library/albums", params={"snapshot": "true"})
    #? the fields that change on every scan travel as headers, so the body can be a 304 (v0.9.20)
    assert response.headers["x-scan-stale"] == "0"
    assert response.json()["album_count"] == 1


def test_a_snapshot_is_the_last_scan_not_the_current_disk(tmp_path, monkeypatch, store):
    directory = seed_album(tmp_path)
    client = make_client(tmp_path, monkeypatch, store)
    client.get("/deadwax/library/albums")

    shutil.rmtree(directory)

    response = client.get("/deadwax/library/albums", params={"snapshot": "true"})
    assert response.headers["x-scan-stale"] == "1"
    assert response.json()["album_count"] == 1
    #? says when that was, so the interface can say how old it is
    assert float(response.headers["x-scanned-at"]) > 0

    assert client.get("/deadwax/library/albums").json()["album_count"] == 0


def test_after_a_restart_the_snapshot_comes_from_the_database(tmp_path, monkeypatch, store):
    from src.routes import library as route

    seed_album(tmp_path)
    make_client(tmp_path, monkeypatch, store).get("/deadwax/library/albums")

    library.clear_scan_cache()
    route._cache_loaded_for = None  # the restart

    response = make_client(tmp_path, monkeypatch, store).get(
        "/deadwax/library/albums", params={"snapshot": "true"}
    )
    body = response.json()

    assert response.headers["x-scan-stale"] == "1"
    assert body["album_count"] == 1
    #? decorated like any other response - the queue is derived, never stored
    assert "no_art" in body["albums"][0]["issues"]


def test_a_snapshot_never_prunes_albums_it_has_not_seen(tmp_path, monkeypatch, store):
    """
    An album filed since the snapshot was taken is absent from it. Pruning on a snapshot would
    delete that album's brand-new import row as an orphan before anyone had looked at it.
    """
    seed_album(tmp_path)
    client = make_client(tmp_path, monkeypatch, store)
    client.get("/deadwax/library/albums")

    just_filed = "Someone/Just Filed (2024)"
    run(store.record_albums_seen([{"path": just_filed, "artist": "Someone", "album": "Just Filed"}],
                                 source="import"))

    client.get("/deadwax/library/albums", params={"snapshot": "true"})
    assert just_filed in run(store.album_reviews())

    #? and a real scan, which has looked, does prune it - so it is the snapshot guard doing this
    client.get("/deadwax/library/albums")
    assert just_filed not in run(store.album_reviews())


def test_deleting_an_album_drops_it_from_the_saved_scan(tmp_path, monkeypatch, store):
    seed_album(tmp_path)
    client = make_client(tmp_path, monkeypatch, store)
    client.get("/deadwax/library/albums")

    response = client.post("/deadwax/library/delete",
                           json={"album_path": "Tame Impala/The Slow Rush (2020)"})
    assert response.status_code == 200

    assert run(store.load_library_cache(str(tmp_path), SCAN_FORMAT)) == []


def test_deleting_a_new_import_takes_it_off_the_badge_at_once(tmp_path, monkeypatch, store):
    """
    Its review row used to stay until the next full scan pruned it, and meanwhile the
    new-imports badge counted an album that no longer existed and couldn't be named (v1.1.5).
    """
    seed_album(tmp_path)
    path = "Tame Impala/The Slow Rush (2020)"
    run(store.record_albums_seen([{"path": path, "album": "The Slow Rush"}], source="import"))
    assert run(store.new_import_summary())["count"] == 1
    client = make_client(tmp_path, monkeypatch, store)

    response = client.post("/deadwax/library/delete", json={"album_path": path})

    assert response.status_code == 200
    assert run(store.new_import_summary())["count"] == 0
    assert path not in run(store.album_reviews())


def test_a_refused_delete_keeps_the_review_row(tmp_path, monkeypatch, store):
    """Nothing was deleted, so nothing is forgotten - here the folder holds no audio directly."""
    notes = tmp_path / "Tame Impala" / "Notes"
    notes.mkdir(parents=True)
    (notes / "rip.log").write_text("the only copy")
    run(store.record_albums_seen([{"path": "Tame Impala/Notes"}], source="import"))
    client = make_client(tmp_path, monkeypatch, store)

    response = client.post("/deadwax/library/delete", json={"album_path": "Tame Impala/Notes"})

    assert response.status_code == 400
    assert notes.is_dir()
    assert "Tame Impala/Notes" in run(store.album_reviews())


# ---------------------------------------------------------------- the track viewer

def test_the_track_viewer_reads_every_tag_live(tmp_path, monkeypatch):
    directory = tmp_path / "Pink Floyd" / "The Dark Side of the Moon (1973)"
    write_flac(directory / "01 - Speak to Me.flac", title="Speak to Me", artist="Pink Floyd",
               tracknumber="1", discnumber="1", genre="Progressive Rock", composer="Nick Mason",
               custom_thing="kept anyway")

    client = make_client(tmp_path, monkeypatch)
    response = client.get("/deadwax/library/tracks",
                          params={"album": "Pink Floyd/The Dark Side of the Moon (1973)"})

    assert response.status_code == 200
    [track] = response.json()["files"]

    assert track["tags"]["genre"] == "Progressive Rock"
    assert track["tags"]["composer"] == "Nick Mason"
    assert track["disc"] == 1 and track["position"] == 1
    assert track["format"] == "flac"
    #? a tag nobody named still reaches the viewer, under the file's own key for it
    assert ["custom_thing", "kept anyway"] in [[k.lower(), v] for k, v in track["raw"]]


def test_the_track_viewer_is_in_running_order(tmp_path, monkeypatch):
    two_disc_album(tmp_path)
    client = make_client(tmp_path, monkeypatch)

    files = client.get("/deadwax/library/tracks",
                       params={"album": "Pink Floyd/The Wall (1979)"}).json()["files"]

    assert [f["tags"]["title"] for f in files] == ["D1T1", "D1T2", "D2T1", "D2T2"]


@pytest.mark.parametrize("attempt", [
    "../../../../etc",
    "Tame Impala/../../../../etc",
    "/etc",
    "",
])
def test_the_track_viewer_refuses_to_read_outside_the_library(tmp_path, monkeypatch, attempt):
    """The second endpoint that turns user input into a filesystem read, so it copies /art's guard."""
    seed_album(tmp_path)
    client = make_client(tmp_path, monkeypatch)
    assert client.get("/deadwax/library/tracks", params={"album": attempt}).status_code == 404


# ---------------------------------------------------------------- disc numbers, written

TWO_DISCS = {
    "artist": "Pink Floyd",
    "album": "The Wall",
    "year": "1979",
    "release_mbid": "mbid-the-wall",
    "tracks": [
        {"position": 1, "title": "In the Flesh", "disc": 1, "disc_position": 1},
        {"position": 2, "title": "The Thin Ice", "disc": 1, "disc_position": 2},
        {"position": 3, "title": "Hey You", "disc": 2, "disc_position": 1},
        {"position": 4, "title": "Nobody Home", "disc": 2, "disc_position": 2},
    ],
}


def test_a_multi_disc_release_is_tagged_per_disc():
    values = tag_values(TWO_DISCS, TWO_DISCS["tracks"][2])
    assert values["tracknumber"] == "1"
    assert values["discnumber"] == "2"


def test_a_single_disc_release_writes_no_disc_number():
    """Or every album in the library would gain a discnumber change and never read 'nothing to change'."""
    release = {**TWO_DISCS, "tracks": [
        {"position": 1, "title": "Speak to Me", "disc": 1, "disc_position": 1},
        {"position": 2, "title": "Breathe", "disc": 1, "disc_position": 2},
    ]}
    values = tag_values(release, release["tracks"][1])
    assert values["tracknumber"] == "2"
    assert "discnumber" not in values


def test_a_tracklist_without_disc_fields_is_numbered_as_it_always_was():
    """A job stored before discs existed must still organize exactly as it would have."""
    release = {**TWO_DISCS, "tracks": [{"position": n, "title": f"T{n}"} for n in (1, 2, 3)]}
    values = tag_values(release, release["tracks"][2])
    assert values["tracknumber"] == "3"
    assert "discnumber" not in values


def test_retagging_a_two_disc_album_writes_the_discs_and_agrees_with_its_preview(tmp_path):
    directory = tmp_path / "Pink Floyd" / "The Wall (1979)"
    #? tagged the old way: one running sequence, no disc
    for track in TWO_DISCS["tracks"]:
        write_flac(directory / f"{track['position']:02d} - {track['title']}.flac",
                   album="The Wall", albumartist="Pink Floyd", artist="Pink Floyd",
                   title=track["title"], tracknumber=str(track["position"]), date="1979")

    plan = plan_retag("Pink Floyd/The Wall (1979)", TWO_DISCS, str(tmp_path))
    hey_you = next(f for f in plan["files"] if f["track_title"] == "Hey You")
    assert hey_you["changes"]["tracknumber"] == {"from": "3", "to": "1"}
    assert hey_you["changes"]["discnumber"] == {"from": "", "to": "2"}

    results = execute_retag(plan, TWO_DISCS, "apply")
    assert results["failed"] == 0

    written = read_current_tags(directory / "03 - Hey You.flac")
    assert written["tracknumber"] == "1"
    assert written["discnumber"] == "2"

    #? the write did exactly what the preview said, so previewing again finds nothing to do
    assert plan_retag("Pink Floyd/The Wall (1979)", TWO_DISCS, str(tmp_path))["empty"]


def test_the_download_request_keeps_the_disc_fields():
    """pydantic drops undeclared fields silently, which would lose discs between browser and organizer."""
    from src.routes.download import Track

    kept = Track(position=3, title="Hey You", disc=2, disc_position=1).model_dump()
    assert kept["disc"] == 2 and kept["disc_position"] == 1


def test_an_unchanged_library_is_a_304_whenever_it_was_scanned(tmp_path, monkeypatch, store):
    """The scan's timing is in headers, so the body - and the ETag - change only with the library."""
    import time
    directory = seed_album(tmp_path)
    client = make_client(tmp_path, monkeypatch, store)
    #? the very first scan enrols the album, and its first_seen appears from the next answer on
    client.get("/deadwax/library/albums")
    first = client.get("/deadwax/library/albums")
    time.sleep(0.01)

    again = client.get("/deadwax/library/albums", headers={"If-None-Match": first.headers["etag"]})
    assert again.status_code == 304
    #? the fresh timing rides on the 304, for the browser to lay over its stored copy
    assert float(again.headers["x-scanned-at"]) >= float(first.headers["x-scanned-at"])

    (directory / "03 - Track 3.flac").write_bytes((directory / "01 - Track 1.flac").read_bytes())
    changed = client.get("/deadwax/library/albums", headers={"If-None-Match": first.headers["etag"]})
    assert changed.status_code == 200 and changed.json()["albums"][0]["track_count"] == 3


def test_tracks_travel_compact_and_say_only_where_they_differ(tmp_path, monkeypatch, store):
    seed_album(tmp_path)
    album = make_client(tmp_path, monkeypatch, store).get("/deadwax/library/albums").json()["albums"][0]
    assert album["track_defaults"]["album"] == "The Slow Rush"
    assert all("album" not in track and "has_title_tag" not in track for track in album["tracks"])


# ---------------------------------------------------------------- the scan without its tracks (2.1.28)

TRACK_KEYS = ("tracks", "track_defaults")


def without_tracks(body):
    """A full answer's body as `?tracks=false` should send it."""
    return {**body, "albums": [{k: v for k, v in album.items() if k not in TRACK_KEYS} for album in body["albums"]]}


def warm_client(tmp_path, monkeypatch, store):
    """Two albums, scanned once - the first scan enrols first_seen, which later answers carry."""
    seed_album(tmp_path)
    seed_album(tmp_path, artist="Portishead", folder="Dummy (1994)", album="Dummy", tracks=3)
    client = make_client(tmp_path, monkeypatch, store)
    client.get("/deadwax/library/albums")
    return client


def test_the_scan_without_its_tracks_is_the_same_answer_less_them(tmp_path, monkeypatch, store):
    """For the iPhone app's editor: every album-level field as the web is sent it, and nothing of a track's."""
    client = warm_client(tmp_path, monkeypatch, store)

    full = client.get("/deadwax/library/albums")
    lean = client.get("/deadwax/library/albums", params={"tracks": "false"})

    assert lean.status_code == 200
    assert lean.json() == without_tracks(full.json())
    #? the same keys in the same order, not merely equal: the body is what the ETag is of
    assert [list(a) for a in lean.json()["albums"]] == [list(a) for a in without_tracks(full.json())["albums"]]
    assert all(key not in album for album in lean.json()["albums"] for key in TRACK_KEYS)
    #? the decoration is there - the queue, its issue types, each album's issues - and the counts
    body = lean.json()
    assert body["album_count"] == 2 and body["queue"] == full.json()["queue"] and body["issue_types"]
    assert all("no_art" in album["issues"] for album in body["albums"])
    assert [a["track_count"] for a in body["albums"]] == [a["track_count"] for a in full.json()["albums"]]
    #? the scan's volatile fields are headers on both
    for name in ("x-scanned-at", "x-scan-seconds", "x-scan-cached", "x-scan-stale"):
        assert name in lean.headers
    assert lean.headers["x-scan-stale"] == "0"
    #? and the default is untouched: the web's answer still carries every track
    assert all(album["tracks"] and album["track_defaults"] for album in full.json()["albums"])


def test_the_two_forms_never_share_an_etag(tmp_path, monkeypatch, store):
    client = warm_client(tmp_path, monkeypatch, store)
    full = client.get("/deadwax/library/albums")
    lean = client.get("/deadwax/library/albums", params={"tracks": "false"})

    assert lean.headers["etag"] != full.headers["etag"]

    again = client.get("/deadwax/library/albums", params={"tracks": "false"},
                       headers={"If-None-Match": lean.headers["etag"]})
    assert again.status_code == 304
    assert "x-scanned-at" in again.headers

    #? each form's ETag is a 200 for the other - never a 304 that hands back the wrong body
    crossed = client.get("/deadwax/library/albums", params={"tracks": "false"},
                         headers={"If-None-Match": full.headers["etag"]})
    assert crossed.status_code == 200 and "tracks" not in crossed.json()["albums"][0]
    crossed = client.get("/deadwax/library/albums", headers={"If-None-Match": lean.headers["etag"]})
    assert crossed.status_code == 200 and crossed.json()["albums"][0]["tracks"]


def test_a_snapshot_without_its_tracks(tmp_path, monkeypatch, store):
    client = warm_client(tmp_path, monkeypatch, store)
    shutil.rmtree(tmp_path / "Portishead")

    full = client.get("/deadwax/library/albums", params={"snapshot": "true"})
    lean = client.get("/deadwax/library/albums", params={"snapshot": "true", "tracks": "false"})

    assert lean.headers["x-scan-stale"] == "1"
    assert lean.json()["album_count"] == 2, "the saved scan, not the disk"
    assert lean.json() == without_tracks(full.json())


def test_a_rescan_without_its_tracks(tmp_path, monkeypatch, store):
    client = warm_client(tmp_path, monkeypatch, store)
    lean_scan = client.get("/deadwax/library/albums", params={"tracks": "false"}).json()

    full = client.post("/deadwax/library/rescan")
    lean = client.post("/deadwax/library/rescan", params={"tracks": "false"})

    assert lean.status_code == 200
    assert lean.json() == without_tracks(full.json())
    assert lean.json() == lean_scan, "a forced read of an unchanged library is the same answer"
    assert all(album["tracks"] for album in full.json()["albums"]), "rescan's default is untouched"


# ---------------------------------------------------------------- the scan's answer, kept (2.1.47)

def test_the_scan_cache_says_which_generation_it_is(tmp_path):
    """It moves when the cache's contents do, and only then - what a kept answer is kept by."""
    directory = seed_album(tmp_path)
    first = scan_library(str(tmp_path))
    assert first["generation"] == library.generation()

    again = scan_library(str(tmp_path))
    assert again["generation"] == first["generation"], "an unchanged library is the same generation"
    assert snapshot_library(str(tmp_path))["generation"] == first["generation"]

    #? a retag leaves the folder's mtime alone - forgetting the folder is what says it changed
    forget_cached_album(str(directory))
    assert library.generation() > first["generation"]
    reread = scan_library(str(tmp_path))
    assert reread["generation"] > first["generation"]

    shutil.rmtree(directory)
    assert scan_library(str(tmp_path))["generation"] > reread["generation"], "a folder gone is another one"


def test_a_forced_rescan_and_a_seeding_are_each_another_generation(tmp_path):
    seed_album(tmp_path)
    first = scan_library(str(tmp_path))
    forced = scan_library(str(tmp_path), force=True)
    assert forced["generation"] > first["generation"]

    saved, _ = drain_cache_changes()
    library.clear_scan_cache()
    cleared = library.generation()
    assert cleared > forced["generation"]
    assert seed_cache(saved) == 1 and library.generation() > cleared
    assert seed_cache(saved) == 0 and library.generation() == cleared + 1, "nothing taken, nothing moved"


def test_a_scan_a_writer_cut_across_says_no_generation(tmp_path, monkeypatch):
    """
    A folder forgotten while a walk is under way - after the walk passed it - leaves albums in hand that
    are no generation of the cache at all. Nothing may be kept by them.
    """
    first = seed_album(tmp_path)
    seed_album(tmp_path, artist="Portishead", folder="Dummy (1994)", album="Dummy")
    scan_library(str(tmp_path))
    forget_cached_album(str(tmp_path / "Portishead" / "Dummy (1994)"))

    real = library.read_album_dir

    def read_and_cut_across(directory, root):
        #? the walk is re-reading Portishead; Tame Impala's cached copy is already in its list
        forget_cached_album(str(first))
        return real(directory, root)

    monkeypatch.setattr(library, "read_album_dir", read_and_cut_across)
    cut = scan_library(str(tmp_path))
    assert cut["album_count"] == 2 and cut["generation"] is None

    monkeypatch.setattr(library, "read_album_dir", real)
    assert scan_library(str(tmp_path))["generation"] == library.generation()


def count_packs(monkeypatch):
    """Counts every encoding of a scan's body, and notes whether any ran on the event loop."""
    from src.routes import library as library_route
    real = library_route._pack_scan
    seen = {"packs": 0, "on_the_loop": 0}

    def counted(result, tracks):
        seen["packs"] += 1
        try:
            asyncio.get_running_loop()
            seen["on_the_loop"] += 1
        except RuntimeError:
            pass
        return real(result, tracks)

    monkeypatch.setattr(library_route, "_pack_scan", counted)
    return seen


def test_an_unchanged_library_is_answered_without_encoding_it_again(tmp_path, monkeypatch, store):
    client = warm_client(tmp_path, monkeypatch, store)
    first = client.get("/deadwax/library/albums")
    seen = count_packs(monkeypatch)

    again = client.get("/deadwax/library/albums", headers={"If-None-Match": first.headers["etag"]})
    assert again.status_code == 304 and seen["packs"] == 0

    #? and a 200 of it - another browser, with no copy - is the kept body, the same bytes
    whole = client.get("/deadwax/library/albums")
    assert whole.status_code == 200 and seen["packs"] == 0
    assert whole.content == first.content and whole.headers["etag"] == first.headers["etag"]
    assert float(whole.headers["x-scanned-at"]) >= float(first.headers["x-scanned-at"]), "the headers are fresh"


def test_the_scans_body_is_never_encoded_on_the_event_loop(tmp_path, monkeypatch, store):
    seed_album(tmp_path)
    client = make_client(tmp_path, monkeypatch, store)
    seen = count_packs(monkeypatch)

    assert client.get("/deadwax/library/albums").status_code == 200
    assert client.get("/deadwax/library/albums", params={"snapshot": "true", "tracks": "false"}).status_code == 200
    assert client.post("/deadwax/library/rescan").status_code == 200
    assert seen["packs"] >= 3 and seen["on_the_loop"] == 0


def test_each_form_keeps_its_own_answer(tmp_path, monkeypatch, store):
    client = warm_client(tmp_path, monkeypatch, store)
    forms = [{}, {"tracks": "false"}, {"snapshot": "true"}, {"snapshot": "true", "tracks": "false"}]
    firsts = [client.get("/deadwax/library/albums", params=form) for form in forms]
    seen = count_packs(monkeypatch)

    for form, first in zip(forms, firsts):
        again = client.get("/deadwax/library/albums", params=form)
        assert again.content == first.content and again.headers["etag"] == first.headers["etag"]
    assert seen["packs"] == 0
    assert "tracks" in firsts[0].json()["albums"][0] and "tracks" not in firsts[1].json()["albums"][0]


def test_a_retag_in_place_is_never_answered_from_before_it(tmp_path, monkeypatch, store):
    """The folder's mtime doesn't move for a retag: the forget is all that says so, and it is enough."""
    import os
    directory = seed_album(tmp_path)
    client = make_client(tmp_path, monkeypatch, store)
    client.get("/deadwax/library/albums")
    before = client.get("/deadwax/library/albums")
    kept = os.stat(directory).st_mtime

    audio = FLAC(str(directory / "01 - Track 1.flac"))
    audio["title"] = "Retitled"
    audio.save()
    os.utime(directory, (kept, kept))
    forget_cached_album(str(directory))

    for form in ({}, {"snapshot": "true"}):
        after = client.get("/deadwax/library/albums", params=form, headers={"If-None-Match": before.headers["etag"]})
        assert after.status_code == 200
        assert after.json()["albums"][0]["tracks"][0]["title"] == "Retitled"


def test_a_review_changing_is_another_answer_though_no_folder_did(tmp_path, monkeypatch, store):
    """What the queue says is part of the body, and no generation of the scan cache: it is compared by value."""
    seed_album(tmp_path)
    client = make_client(tmp_path, monkeypatch, store)
    client.get("/deadwax/library/albums")
    before = client.get("/deadwax/library/albums")
    album = before.json()["albums"][0]
    assert album["needs_attention"]
    generation = library.generation()

    ignored = client.post("/deadwax/library/queue/ignore", json={"album_path": album["path"], "issues": album["issues"]})
    assert ignored.status_code == 200

    after = client.get("/deadwax/library/albums", headers={"If-None-Match": before.headers["etag"]})
    assert library.generation() == generation, "no folder changed"
    assert after.status_code == 200 and not after.json()["albums"][0]["needs_attention"]
    assert after.json()["queue"]["total"] == 0


def test_a_kept_answer_is_gzipped_only_for_an_asker_who_accepts_it(tmp_path, monkeypatch, store):
    import gzip
    import json
    client = warm_client(tmp_path, monkeypatch, store)

    packed = client.get("/deadwax/library/albums", headers={"Accept-Encoding": "gzip"})
    assert packed.headers["content-encoding"] == "gzip" and "accept-encoding" in packed.headers["vary"].lower()

    plain = client.get("/deadwax/library/albums", headers={"Accept-Encoding": "identity"})
    assert "content-encoding" not in plain.headers
    assert plain.content == packed.content and json.loads(plain.content)["album_count"] == 2
    assert plain.headers["etag"] == packed.headers["etag"]

    #? and through the app's own compression: once, not twice
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    from starlette.middleware.gzip import GZipMiddleware
    from src.routes import library as library_route
    app = FastAPI()
    app.state.store = store
    app.include_router(library_route.router, prefix="/deadwax/library")
    app.add_middleware(GZipMiddleware, minimum_size=1024, compresslevel=6)
    with TestClient(app).stream("GET", "/deadwax/library/albums", headers={"Accept-Encoding": "gzip"}) as raw:
        body = b"".join(raw.iter_raw())
        assert raw.headers["content-encoding"] == "gzip"
    assert gzip.decompress(body) == plain.content


def test_a_rescan_drops_the_librarys_kept_album_lists(tmp_path, monkeypatch, store):
    """(2.1.49) src/index_keep.py: Rescan is "show me what is really there"."""
    from src import index_keep

    client = warm_client(tmp_path, monkeypatch, store)
    began = index_keep.epoch()
    client.get("/deadwax/library/albums")
    assert index_keep.epoch() == began, "a look at the library drops nothing"

    assert client.post("/deadwax/library/rescan").status_code == 200
    assert index_keep.epoch() != began
