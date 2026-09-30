"""
The store index and "already have it" (step 2 of the multi-user plan, 2.0.0-player.7).

store_album keeps every album folder in the library under an id that survives a rename (step 5's
per-user ledger keys on it), fed by every real scan and by every writer that moves or makes an
album. Find reads it before searching, /enqueue and the retries before asking slskd, and one lock
per release covers the check, the enqueue and the job - so a pressing already held complete, or
already on its way, is never fetched a second time.

Real files with real tags wherever the disk decides the answer (write_flac, as test_library.py),
a real SQLite store, and fakes for slskd shaped like the ones the other download tests use.
"""

import asyncio
import logging
import shutil
import sqlite3
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from src import library, poller, store_index
from src.config import Config
from src.library import SCAN_FORMAT, clear_scan_cache
from src.poller import poll_downloads_once, retry_next_peer, retry_same_peer
from src.routes import download as routes
from src.routes import library as library_routes
from src.store import JobStore, pair_moved
from src.store_index import (held_copy, index_folder, library_relative, other_pressings, release_lock,
                             seed_from_saved_scan)
from tests.test_library import write_flac

ROOT = "/music"
DUMMY = "Portishead/Dummy (1994)"


def run(coroutine):
    return asyncio.run(coroutine)


@pytest.fixture
def store(tmp_path):
    job_store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    job_store.init()
    return job_store


@pytest.fixture(autouse=True)
def fresh(monkeypatch):
    """Every module-level cache emptied, Navidrome not set up, organizing off unless a test says."""
    library.clear_scan_cache()
    library_routes._cache_loaded_for = None
    monkeypatch.setattr(library_routes, "_HELD_RENAMES", {})
    monkeypatch.setattr(library_routes, "_APPLY_LOCKS", {})
    monkeypatch.setattr(store_index, "_FILING_NOW", {})
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "off")
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", None)
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "off")
    yield
    library.clear_scan_cache()
    library_routes._cache_loaded_for = None


def rows(store, **where):
    with sqlite3.connect(store.path) as connection:
        connection.row_factory = sqlite3.Row
        found = [dict(r) for r in connection.execute("SELECT * FROM store_album ORDER BY id")]
    return [r for r in found if all(r[k] == v for k, v in where.items())]


def went(store, row_id, when, path=None):
    """Say when a tombstone went (and, for two at one path, where it was) - by hand, to order them."""
    with sqlite3.connect(store.path) as connection:
        if path:
            connection.execute("UPDATE store_album SET gone_at = ?, path = ? WHERE id = ?", (when, path, row_id))
        else:
            connection.execute("UPDATE store_album SET gone_at = ? WHERE id = ?", (when, row_id))


def case_insensitive(tmp_path) -> bool:
    """Whether this disk opens a folder under any spelling - APFS by default, exFAT, CIFS."""
    (tmp_path / "Probe").mkdir()
    return (tmp_path / "probe").exists()


def album(path=DUMMY, release="rel-1", group="grp-1", **extra):
    """A scan album (library.read_album_dir's shape), as far as the index reads it."""
    return {"path": path, "release_mbid": release, "release_group_mbid": group, "artist": "Portishead",
            "album": "Dummy", "year": "1994", "edition": "", "track_count": 2, "formats": ["flac"], **extra}


def on_disk(root, folder=DUMMY, release="rel-1", group="grp-1", tracks=2, first=1, disc=None, ext="flac"):
    """An album folder deadwax filed, tagged with its release (and a disc, for a set)."""
    directory = root / folder
    for n in range(first, first + tracks):
        tags = {"album": "Dummy", "albumartist": "Portishead", "artist": "Portishead", "title": f"Track {n}",
                "tracknumber": str(n), "date": "1994", "musicbrainz_albumid": release,
                "musicbrainz_releasegroupid": group}
        if disc:
            tags["discnumber"] = str(disc)
        #? another extension holds the same tagged audio (mutagen reads by content) - what a FLAC
        #? and an MP3 of the same tracks side by side read as
        write_flac(directory / f"{n:02d} - Track {n}.{ext}", **tags)
    return directory


def release_of(tracks=2, discs=None):
    """A release payload with `tracks` tracks - or `discs` discs of that many each."""
    if discs:
        listed = [{"position": (d - 1) * tracks + n, "title": f"Track {n}", "disc": d, "disc_position": n}
                  for d in range(1, discs + 1) for n in range(1, tracks + 1)]
    else:
        listed = [{"position": n, "title": f"Track {n}"} for n in range(1, tracks + 1)]
    return {**RELEASE, "tracks": listed}


TRACKS = [{"position": 1, "title": "Track 1"}, {"position": 2, "title": "Track 2"}]
RELEASE = {"artist": "Portishead", "album": "Dummy", "year": "1994", "release_mbid": "rel-1",
           "release_group_mbid": "grp-1", "tracks": TRACKS}


# ================================================================ the table

def test_a_database_from_before_this_gains_the_table(tmp_path):
    path = tmp_path / "old.db"
    with sqlite3.connect(path) as connection:
        connection.execute("""CREATE TABLE jobs (id INTEGER PRIMARY KEY AUTOINCREMENT, release_mbid TEXT,
            artist TEXT, album TEXT, year TEXT, username TEXT NOT NULL, directory TEXT,
            release_json TEXT NOT NULL, files_json TEXT NOT NULL, status TEXT NOT NULL, error TEXT,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""")
    old = JobStore(str(path))
    old.init()

    assert run(old.index_upsert(ROOT, album())) == 1
    with sqlite3.connect(path) as connection:
        indexes = {row[1] for row in connection.execute("PRAGMA index_list(jobs)")}
    assert "idx_jobs_release" in indexes


def test_an_album_is_recorded_once_and_updated_in_place(store):
    first = run(store.index_upsert(ROOT, album()))
    again = run(store.index_upsert(ROOT, album(track_count=3, formats=["mp3", "flac"], release="")))

    assert first == again
    [row] = rows(store)
    #? '' is how the scan says untagged - NULL here, so two untagged folders compare alike
    assert (row["track_count"], row["formats"], row["release_mbid"], row["state"]) == \
        (3, '["flac", "mp3"]', None, "present")


def test_a_missing_row_at_the_same_path_with_the_same_release_comes_back(store):
    first = run(store.index_upsert(ROOT, album()))
    run(store.index_gone(ROOT, DUMMY, "missing"))

    assert run(store.index_upsert(ROOT, album())) == first
    assert rows(store, id=first)[0]["state"] == "present" and rows(store, id=first)[0]["gone_at"] is None


def test_a_scan_finding_a_missing_folder_elsewhere_gives_it_its_row_back(store):
    """Moved outside deadwax: its old path gone, the same release found at a new one."""
    first = run(store.index_upsert(ROOT, album()))
    run(store.index_gone(ROOT, DUMMY, "missing"))

    run(store.index_reconcile(ROOT, [album(path="Portishead/Dummy")]))
    assert [(r["id"], r["path"], r["state"]) for r in rows(store)] == [(first, "Portishead/Dummy", "present")]


def test_a_folder_deadwax_writes_never_takes_another_folders_row(store):
    """
    A fresh download of a release whose share is unmounted is a new folder, not the share's -
    reviving by release there walked off with the share's id, and gave the share a new one when
    it came back.
    """
    share = run(store.index_upsert(ROOT, album(path="Share/Dummy")))
    run(store.index_gone(ROOT, "Share/Dummy", "missing"))

    filed = run(store.index_upsert(ROOT, album()))
    assert filed != share
    assert rows(store, id=share)[0]["state"] == "missing"

    #? and the share, back, is its own row again
    run(store.index_reconcile(ROOT, [album(), album(path="Share/Dummy")]))
    assert rows(store, id=share)[0]["state"] == "present"


def test_a_deleted_album_filed_again_is_a_new_album(store):
    """Only `missing` rows come back - a deleted one stays deleted at the same path or any other."""
    first = run(store.index_upsert(ROOT, album()))
    run(store.index_gone(ROOT, DUMMY, "deleted"))

    again = run(store.index_upsert(ROOT, album()))
    run(store.index_reconcile(ROOT, [album(), album(path="Portishead/Dummy")]))

    assert again != first
    assert rows(store, id=first)[0]["state"] == "deleted"
    assert len(rows(store, state="present")) == 2


def test_a_merged_folder_is_never_brought_back(store):
    target = run(store.index_upsert(ROOT, album(path="Radiohead/OK Computer (1997)")))
    source = run(store.index_upsert(ROOT, album(path="Radiohead/OK Computer (Disc 2)")))
    run(store.index_merge(ROOT, "Radiohead/OK Computer (Disc 2)", "Radiohead/OK Computer (1997)"))

    assert run(store.index_upsert(ROOT, album(path="Radiohead/OK Computer (Disc 2)"))) not in (source, target)
    assert rows(store, id=source)[0]["state"] == "merged"


def two_tombstones_at_dummy(store):
    """Two `missing` rows once at Dummy's path: the OLDER row went last, the newer long ago."""
    older = run(store.index_upsert(ROOT, album(path="Portishead/Dummy [a]")))
    newer = run(store.index_upsert(ROOT, album(path="Portishead/Dummy [b]")))
    run(store.index_gone(ROOT, "Portishead/Dummy [a]", "missing"))
    run(store.index_gone(ROOT, "Portishead/Dummy [b]", "missing"))
    went(store, older, "2026-09-20T00:00:00+00:00", DUMMY)
    went(store, newer, "2026-01-01T00:00:00+00:00", DUMMY)
    return older, newer


def test_the_same_folder_back_takes_the_tombstone_that_went_last(store):
    """Not the highest id: that is only the row made last, and here an older copy's."""
    older, newer = two_tombstones_at_dummy(store)
    assert run(store.index_upsert(ROOT, album())) == older
    assert rows(store, id=newer)[0]["state"] == "missing"


def test_a_scan_finding_the_same_folder_back_takes_the_tombstone_that_went_last(store):
    older, _ = two_tombstones_at_dummy(store)
    run(store.index_reconcile(ROOT, [album()]))
    assert [r["id"] for r in rows(store, state="present")] == [older]


def test_a_move_takes_the_tombstone_at_its_old_path_that_went_last(store):
    older, _ = two_tombstones_at_dummy(store)
    assert run(store.index_move(ROOT, DUMMY, "Portishead/Dummy (1994) [CD]")) == older


def test_a_move_a_scan_has_already_paired_changes_nothing(store):
    """
    Donda moved on disk, a scan paired it at Ye/Donda, and only then did the writer say so - with
    only an OLDER album's tombstone left at the old path. Merging the live row into that would
    hand Donda that album's id.
    """
    stranger = run(store.index_upsert(ROOT, album(path="Kanye West/Donda", release="rel-other")))
    run(store.index_gone(ROOT, "Kanye West/Donda", "missing"))
    donda = run(store.index_upsert(ROOT, album(path="Ye/Donda")))

    assert run(store.index_move(ROOT, "Kanye West/Donda", "Ye/Donda", "rel-1")) == donda
    assert {r["id"]: (r["path"], r["state"]) for r in rows(store)} == {
        stranger: ("Kanye West/Donda", "missing"), donda: ("Ye/Donda", "present")}


# ---------------------------------------------------------------- moves outside deadwax

def test_the_discs_of_a_set_moved_together_keep_their_own_ids(store):
    """An artist folder renamed by hand: each disc folder keeps its name, and so its row."""
    one = run(store.index_upsert(ROOT, album(path="Radiohead/OK Computer (Disc 1)", release="okc")))
    two = run(store.index_upsert(ROOT, album(path="Radiohead/OK Computer (Disc 2)", release="okc")))

    run(store.index_reconcile(ROOT, [album(path="Radiohead (band)/OK Computer (Disc 1)", release="okc"),
                                     album(path="Radiohead (band)/OK Computer (Disc 2)", release="okc")]))

    assert {r["id"]: r["path"] for r in rows(store)} == {
        one: "Radiohead (band)/OK Computer (Disc 1)", two: "Radiohead (band)/OK Computer (Disc 2)"}


def test_two_copies_that_cant_be_told_apart_get_new_rows_rather_than_a_guess(store):
    first = run(store.index_upsert(ROOT, album(path="Portishead/Dummy [FLAC]")))
    second = run(store.index_upsert(ROOT, album(path="Portishead/Dummy [MP3]")))

    run(store.index_reconcile(ROOT, [album(path="Portishead/Dummy A"), album(path="Portishead/Dummy B")]))

    assert {r["id"]: r["state"] for r in rows(store) if r["id"] in (first, second)} == {first: "missing", second: "missing"}
    assert len(rows(store, state="present")) == 2


def test_pairing_is_one_of_each_or_one_of_each_by_folder_name():
    assert pair_moved(["B/Dummy (1994)"], [(7, "A/Dummy")]) == {"B/Dummy (1994)": 7}
    assert pair_moved(["B/X (Disc 1)", "B/X (Disc 2)"], [(1, "A/X (Disc 1)"), (2, "A/X (Disc 2)")]) == \
        {"B/X (Disc 1)": 1, "B/X (Disc 2)": 2}
    #? a name two rows share settles nothing
    assert pair_moved(["B/X", "C/Y"], [(1, "A/X"), (2, "D/X")]) == {}
    assert pair_moved(["B/X", "C/Y"], [(1, "A/Q"), (2, "D/R")]) == {}


def test_a_rename_pairs_with_what_this_scan_found_gone_before_older_tombstones(store):
    """An old copy's tombstone of the release made every later rename of it ambiguous."""
    old_copy = run(store.index_upsert(ROOT, album(path="Old/Dummy [MP3]")))
    run(store.index_gone(ROOT, "Old/Dummy [MP3]", "missing"))
    live = run(store.index_upsert(ROOT, album(path="Portishead/Dummy")))

    run(store.index_reconcile(ROOT, [album(path="Portishead/Dummy (1994)")]))

    assert {r["id"]: (r["path"], r["state"]) for r in rows(store)} == {
        old_copy: ("Old/Dummy [MP3]", "missing"), live: ("Portishead/Dummy (1994)", "present")}


# ---------------------------------------------------------------- a scan older than a writer

def holds_audio_only(*paths):
    return lambda path: path in paths


def test_a_scan_that_walked_past_a_deleted_album_does_not_bring_it_back(store):
    first = run(store.index_upsert(ROOT, album()))
    run(store.index_gone(ROOT, DUMMY, "deleted"))

    #? the walk listed Dummy before the delete; the folder is gone by the time it lands
    run(store.index_reconcile(ROOT, [album(), album(path="Portishead/Third", release="rel-3")],
                              still_there=holds_audio_only("Portishead/Third")))

    assert rows(store, id=first)[0]["state"] == "deleted"
    assert [r["path"] for r in rows(store, state="present")] == ["Portishead/Third"]


def test_a_scan_that_walked_past_a_renamed_album_leaves_no_row_at_its_old_name(store):
    first = run(store.index_upsert(ROOT, album(path="Kanye West/Donda")))
    run(store.index_move(ROOT, "Kanye West/Donda", "Ye/Donda"))

    run(store.index_reconcile(ROOT, [album(path="Kanye West/Donda")], still_there=holds_audio_only("Ye/Donda")))

    assert [(r["id"], r["path"], r["state"]) for r in rows(store)] == [(first, "Ye/Donda", "present")]


def test_a_scan_does_not_undo_what_a_writer_wrote_after_it_began(store):
    first = run(store.index_upsert(ROOT, album(release="rel-new")))
    began = (datetime.now(timezone.utc) - timedelta(seconds=30)).timestamp()

    #? the walk read the old tags before an apply re-tagged the album in place
    run(store.index_reconcile(ROOT, [album(release="rel-old")], since=began))
    assert rows(store, id=first)[0]["release_mbid"] == "rel-new"

    #? a scan that began after the write does update it
    run(store.index_reconcile(ROOT, [album(release="rel-old")], since=datetime.now(timezone.utc).timestamp() + 2))
    assert rows(store, id=first)[0]["release_mbid"] == "rel-old"


def test_a_move_finds_its_row_even_just_marked_missing(store):
    """A Find or a scan can tombstone the old path in the moment between the rename and index_move."""
    first = run(store.index_upsert(ROOT, album(path="Kanye West/Donda")))
    run(store.index_gone(ROOT, "Kanye West/Donda", "missing"))

    assert run(store.index_move(ROOT, "Kanye West/Donda", "Ye/Donda")) == first
    assert [(r["id"], r["path"], r["state"]) for r in rows(store)] == [(first, "Ye/Donda", "present")]


def test_a_scan_marks_what_it_no_longer_found_missing(store):
    run(store.index_upsert(ROOT, album()))
    run(store.index_upsert(ROOT, album(path="Portishead/Third (2008)", release="rel-3")))

    run(store.index_reconcile(ROOT, [album()]))

    assert [(r["path"], r["state"]) for r in rows(store)] == [(DUMMY, "present"), ("Portishead/Third (2008)", "missing")]
    assert rows(store, state="missing")[0]["gone_at"]


def test_an_empty_scan_marks_nothing_missing(store):
    """An empty library is far more often an unmounted share than a deleted collection."""
    run(store.index_upsert(ROOT, album()))
    run(store.index_reconcile(ROOT, []))
    assert rows(store)[0]["state"] == "present"


def test_a_folder_moved_between_scans_keeps_its_id(store):
    first = run(store.index_upsert(ROOT, album()))
    run(store.index_reconcile(ROOT, [album(path="Portishead/Dummy [CD]")]))
    assert [(r["id"], r["path"], r["state"]) for r in rows(store)] == [(first, "Portishead/Dummy [CD]", "present")]


def test_an_unchanged_scan_writes_nothing(store):
    run(store.index_reconcile(ROOT, [album(), album(path="Portishead/Third (2008)", release="rel-3")]))
    assert run(store.index_reconcile(ROOT, [album(), album(path="Portishead/Third (2008)", release="rel-3")])) == (0, 0)


def test_a_move_keeps_the_id(store):
    first = run(store.index_upsert(ROOT, album()))
    assert run(store.index_move(ROOT, DUMMY, "Portishead/Dummy (1994) [Remaster]")) == first
    assert rows(store, id=first)[0]["path"] == "Portishead/Dummy (1994) [Remaster]"


def test_a_move_onto_a_folder_already_indexed_keeps_the_row_with_a_history(store):
    first = run(store.index_upsert(ROOT, album()))
    newcomer = run(store.index_upsert(ROOT, album(path="Portishead/Dummy (1994) [Remaster]")))

    run(store.index_move(ROOT, DUMMY, "Portishead/Dummy (1994) [Remaster]"))

    assert rows(store, id=first)[0]["path"] == "Portishead/Dummy (1994) [Remaster]"
    assert (rows(store, id=newcomer)[0]["state"], rows(store, id=newcomer)[0]["merged_into"]) == ("merged", first)


def test_a_merged_disc_folder_points_at_the_folder_it_joined(store):
    target = run(store.index_upsert(ROOT, album(path="Radiohead/OK Computer (1997)")))
    source = run(store.index_upsert(ROOT, album(path="Radiohead/OK Computer (Disc 2)")))

    assert run(store.index_merge(ROOT, "Radiohead/OK Computer (Disc 2)", "Radiohead/OK Computer (1997)")) == target
    row = rows(store, id=source)[0]
    assert (row["state"], row["merged_into"]) == ("merged", target) and row["gone_at"]


def test_a_merge_into_a_folder_nobody_indexed_is_a_move(store):
    source = run(store.index_upsert(ROOT, album(path="Radiohead/OK Computer (Disc 2)")))
    run(store.index_merge(ROOT, "Radiohead/OK Computer (Disc 2)", "Radiohead/OK Computer (1997)"))
    assert rows(store, id=source)[0]["path"] == "Radiohead/OK Computer (1997)"


def test_other_pressings_are_the_same_album_and_another_release(store):
    run(store.index_upsert(ROOT, album()))
    run(store.index_upsert(ROOT, album(path="Portishead/Dummy (1994) [2014 vinyl]", release="rel-vinyl")))
    run(store.index_upsert(ROOT, album(path="Portishead/Third (2008)", release="rel-3", group="grp-3")))

    assert [r["path"] for r in run(store.index_pressings(ROOT, "grp-1", "rel-1"))] == ["Portishead/Dummy (1994) [2014 vinyl]"]


def test_the_index_is_filled_from_the_saved_scan_once(tmp_path, store):
    root = str(tmp_path / "music")
    run(store.save_library_cache(root, [(f"{root}/{DUMMY}", 1.0, album())], [], SCAN_FORMAT))

    assert run(seed_from_saved_scan(store, root)) == 1
    assert [(r["path"], r["release_mbid"]) for r in rows(store)] == [(DUMMY, "rel-1")]

    #? an index with anything in it is never seeded again - the scans keep it now
    run(store.save_library_cache(root, [(f"{root}/Portishead/Third (2008)", 1.0, album(path="x"))], [], SCAN_FORMAT))
    assert run(seed_from_saved_scan(store, root)) == 0


def test_an_unavailable_store_indexes_nothing_quietly(tmp_path):
    broken = JobStore(str(tmp_path / "nowhere" / "deadwax.db"))
    assert run(broken.index_upsert(ROOT, album())) is None
    assert run(broken.index_present(ROOT, "rel-1")) == []
    assert run(held_copy(broken, ROOT, "rel-1", release_of(2))) is None


# ================================================================ the checks

def test_held_complete(tmp_path, store):
    root = str(tmp_path)
    run(index_folder(store, root, on_disk(tmp_path)))

    held = run(held_copy(store, root, "rel-1", release_of(2)))

    assert held == {"path": DUMMY, "paths": [DUMMY], "artist": "Portishead", "album": "Dummy", "edition": "",
                    "track_count": 2, "expected_tracks": 2, "formats": ["flac"], "complete": True,
                    "fills_gaps": False, "filed_to": None}


def test_held_in_part(tmp_path, store):
    root = str(tmp_path)
    run(index_folder(store, root, on_disk(tmp_path, tracks=1)))
    held = run(held_copy(store, root, "rel-1", release_of(2)))
    assert (held["track_count"], held["expected_tracks"], held["complete"]) == (1, 2, False)


def test_no_tracklist_means_whatever_is_there_is_all_of_it(tmp_path, store):
    run(index_folder(store, str(tmp_path), on_disk(tmp_path, tracks=1)))
    assert run(held_copy(store, str(tmp_path), "rel-1", {"tracks": []}))["complete"]


def test_a_release_stored_one_folder_per_disc_is_summed(tmp_path, store):
    root = str(tmp_path)
    run(index_folder(store, root, on_disk(tmp_path, "Radiohead/OK Computer (Disc 1)", release="okc", disc=1)))
    run(index_folder(store, root, on_disk(tmp_path, "Radiohead/OK Computer (Disc 2)", release="okc", disc=2)))

    held = run(held_copy(store, root, "okc", release_of(2, discs=2)))

    assert held["paths"] == ["Radiohead/OK Computer (Disc 1)", "Radiohead/OK Computer (Disc 2)"]
    assert (held["track_count"], held["expected_tracks"], held["complete"]) == (4, 4, True)


def test_the_same_tracks_twice_are_not_a_complete_pressing(tmp_path, store):
    """A FLAC and an MP3 of tracks 1-5 of a 10-track release, side by side: 5 of 10, not 10."""
    root = str(tmp_path)
    on_disk(tmp_path, tracks=5)
    on_disk(tmp_path, tracks=5, ext="mp3")
    run(index_folder(store, root, tmp_path / DUMMY))

    held = run(held_copy(store, root, "rel-1", release_of(10)))

    assert (held["track_count"], held["expected_tracks"], held["complete"], held["formats"]) == \
        (5, 10, False, ["flac", "mp3"])


def test_two_part_copies_missing_the_same_track_are_not_complete(tmp_path, store):
    root = str(tmp_path)
    run(index_folder(store, root, on_disk(tmp_path, tracks=9)))
    run(index_folder(store, root, on_disk(tmp_path, "Portishead/Dummy (2011)", tracks=9)))

    held = run(held_copy(store, root, "rel-1", release_of(10)))
    assert (held["track_count"], held["complete"]) == (9, False)


def test_audio_that_is_no_track_of_the_release_fills_nothing(tmp_path, store):
    root = str(tmp_path)
    directory = on_disk(tmp_path, tracks=2)
    write_flac(directory / "Portishead interview.flac", musicbrainz_albumid="rel-1", tracknumber="99")
    run(index_folder(store, root, directory))

    held = run(held_copy(store, root, "rel-1", release_of(3)))
    assert (held["track_count"], held["expected_tracks"], held["complete"]) == (2, 3, False)


def test_titles_place_tracks_whatever_their_numbers_say(tmp_path, store):
    """
    A stray disc tag (Jackpot Juicer's "Untitled 2" alone on disc 2 of a one-disc album), beets
    numbering a set across discs, and running numbers with no disc tag from before v0.6.5: the
    titles are the release's, so all of it is there.
    """
    root = str(tmp_path)
    folder = tmp_path / "A/B (2020)"
    for name, tags in (("01 - One.flac", {"title": "One", "tracknumber": "1", "discnumber": "2"}),
                       ("02 - Two.flac", {"title": "Two", "tracknumber": "2"}),
                       ("03 - Three.flac", {"title": "Three", "tracknumber": "3", "discnumber": "2"}),
                       ("04 - Four.flac", {"title": "Four", "tracknumber": "4"})):
        write_flac(folder / name, musicbrainz_albumid="set", **tags)
    run(index_folder(store, root, folder))
    release = {**RELEASE, "release_mbid": "set", "tracks": [
        {"position": 1, "title": "One", "disc": 1, "disc_position": 1},
        {"position": 2, "title": "Two", "disc": 1, "disc_position": 2},
        {"position": 3, "title": "Three", "disc": 2, "disc_position": 1},
        {"position": 4, "title": "Four", "disc": 2, "disc_position": 2}]}

    held = run(held_copy(store, root, "set", release))
    assert (held["track_count"], held["complete"]) == (4, True)


def test_untitled_files_are_placed_by_their_running_number_too(tmp_path, store):
    """No titles to go on, a set numbered across its discs: disc 2's files say 3 and 4."""
    root = str(tmp_path)
    folder = tmp_path / "A/B (2020)"
    for name, tags in (("a.flac", {"tracknumber": "1", "discnumber": "1"}), ("b.flac", {"tracknumber": "2", "discnumber": "1"}),
                       ("c.flac", {"tracknumber": "3", "discnumber": "2"}), ("d.flac", {"tracknumber": "4"})):
        write_flac(folder / name, musicbrainz_albumid="rel-1", **tags)
    run(index_folder(store, root, folder))

    held = run(held_copy(store, root, "rel-1", release_of(2, discs=2)))
    assert (held["track_count"], held["complete"]) == (4, True)


def test_a_title_the_release_doesnt_have_still_counts_by_its_number(tmp_path, store):
    root = str(tmp_path)
    directory = on_disk(tmp_path, tracks=1)
    write_flac(directory / "02 - Track 2 (Remastered).flac", title="Track 2 (Remastered)", tracknumber="2",
               musicbrainz_albumid="rel-1")
    run(index_folder(store, root, directory))
    assert run(held_copy(store, root, "rel-1", release_of(2)))["complete"]


def test_a_file_placed_by_its_title_never_stands_in_for_another_track(tmp_path, store):
    """Track 2's file mistagged 3: it is track 2, and track 3 is still missing."""
    root = str(tmp_path)
    directory = on_disk(tmp_path, tracks=1)
    write_flac(directory / "03 - Track 2.flac", title="Track 2", tracknumber="3", musicbrainz_albumid="rel-1")
    run(index_folder(store, root, directory))

    held = run(held_copy(store, root, "rel-1", release_of(3)))
    assert (held["track_count"], held["complete"]) == (2, False)


def with_video(audio=2, video=1):
    """A CD of `audio` tracks and a DVD of `video` - the DVD's marked as both builders mark them."""
    tracks = [{"position": n, "title": f"Track {n}", "disc": 1, "disc_position": n} for n in range(1, audio + 1)]
    tracks += [{"position": audio + n, "title": f"Live {n}", "disc": 2, "disc_position": n, "video": True}
               for n in range(1, video + 1)]
    return {**RELEASE, "tracks": tracks}


def test_a_dvds_tracks_are_not_waited_for(tmp_path, store):
    """A CD+DVD deluxe held whole: the DVD's tracks never arrive as audio."""
    root = str(tmp_path)
    run(index_folder(store, root, on_disk(tmp_path)))

    held = run(held_copy(store, root, "rel-1", with_video(2, 2)))
    assert (held["track_count"], held["expected_tracks"], held["complete"]) == (2, 2, True)


def test_a_release_that_is_all_video_keeps_every_track(tmp_path, store):
    """A concert film: with nothing left to compare, any one file would read as all of it."""
    root = str(tmp_path)
    run(index_folder(store, root, on_disk(tmp_path, tracks=1)))

    held = run(held_copy(store, root, "rel-1", with_video(0, 2)))
    assert (held["expected_tracks"], held["complete"]) == (2, False)


def test_the_requests_keep_which_tracks_are_video():
    """Undeclared, pydantic would drop it and a CD+DVD pressing could never read as complete."""
    track = {"position": 1, "title": "Live 1", "video": True}
    assert routes.FindCandidatesRequest(**{**RELEASE, "tracks": [track]}).model_dump()["tracks"][0]["video"] is True
    assert enqueue_body(release={**RELEASE, "tracks": [track]}).model_dump()["release"]["tracks"][0]["video"] is True


def test_files_with_no_readable_place_are_counted_instead(tmp_path, store):
    """Untagged numbers and names that aren't deadwax's: nothing to key by, so they are counted."""
    root = str(tmp_path)
    for name in ("a.flac", "b.flac"):
        write_flac(tmp_path / DUMMY / name, musicbrainz_albumid="rel-1")
    run(index_folder(store, root, tmp_path / DUMMY))

    held = run(held_copy(store, root, "rel-1", release_of(2)))
    assert (held["track_count"], held["complete"]) == (2, True)


def test_a_folder_that_has_gone_is_marked_missing_not_held(tmp_path, store):
    root = str(tmp_path)
    directory = on_disk(tmp_path)
    run(index_folder(store, root, directory))
    shutil.rmtree(directory)

    assert run(held_copy(store, root, "rel-1", release_of(2))) is None
    assert rows(store)[0]["state"] == "missing"


def test_a_folder_whose_first_file_is_not_this_release_is_not_held(tmp_path, store):
    """A folder shared with an untagged rip: the download goes ahead, filing's duplicate rules decide."""
    root = str(tmp_path)
    directory = on_disk(tmp_path)
    run(store.index_upsert(root, album()))
    write_flac(directory / "00 - Intro.flac", title="Intro", tracknumber="0")

    assert run(held_copy(store, root, "rel-1", release_of(2))) is None
    assert rows(store)[0]["state"] == "present", "it is still there - just not provably this release"


def test_other_pressings_that_have_gone_are_left_out(tmp_path, store):
    root = str(tmp_path)
    run(index_folder(store, root, on_disk(tmp_path)))
    vinyl = on_disk(tmp_path, "Portishead/Dummy (1994) [2014 vinyl]", release="rel-vinyl")
    run(index_folder(store, root, vinyl))
    assert [p["path"] for p in run(other_pressings(store, root, "grp-1", "rel-1"))] == ["Portishead/Dummy (1994) [2014 vinyl]"]

    shutil.rmtree(vinyl)
    assert run(other_pressings(store, root, "grp-1", "rel-1")) == []


def job_in(store, status, release_mbid="rel-1", user="bob", error=None, age=None, files=2, release=None):
    async def go():
        wanted = [{"filename": f"share\\Dummy\\0{n}.flac", "size": 1} for n in range(1, files + 1)]
        job_id = await store.create_job(user, "share\\Dummy", wanted, {**(release or RELEASE), "release_mbid": release_mbid})
        await store.update_status(job_id, status, error)
        return job_id
    job_id = run(go())
    if age is not None:
        stamp = (datetime.now(timezone.utc) - age).isoformat(timespec="seconds")
        with sqlite3.connect(store.path) as connection:
            connection.execute("UPDATE jobs SET updated_at = ? WHERE id = ?", (stamp, job_id))
    return job_id


@pytest.mark.parametrize("status", ["queued", "downloading"])
def test_a_download_under_way_is_in_flight(store, status):
    job_id = job_in(store, status)
    assert run(store.in_flight_job("rel-1"))["id"] == job_id
    assert run(store.in_flight_job("rel-other")) is None


def test_the_job_being_retried_is_not_in_flight_against_itself(store):
    job_id = job_in(store, "queued")
    assert run(store.in_flight_job("rel-1", excluding_job_id=job_id)) is None


def test_filing_is_in_flight_for_an_hour_and_no_longer(store):
    """A job stranded in `organizing` by a restart must not block its release for ever."""
    job_in(store, "organizing", age=timedelta(minutes=10))
    assert run(store.in_flight_job("rel-1"))["status"] == "organizing"

    with sqlite3.connect(store.path) as connection:
        connection.execute("UPDATE jobs SET updated_at = ?",
                           ((datetime.now(timezone.utc) - timedelta(hours=2)).isoformat(timespec="seconds"),))
    assert run(store.in_flight_job("rel-1")) is None


def test_complete_is_in_flight_only_on_its_way_to_being_filed(store):
    job_in(store, "complete", age=timedelta(seconds=30))
    assert run(store.in_flight_job("rel-1"))["status"] == "complete"
    #? with organizing off, complete is where a download ends
    assert run(store.in_flight_job("rel-1", filing=False)) is None


def test_a_download_that_completed_while_organizing_was_off_is_never_on_its_way(store):
    """The poller moves complete to organizing in the same pass - one still complete minutes on is stranded."""
    job_in(store, "complete", age=timedelta(minutes=3))
    assert run(store.in_flight_job("rel-1", filing=True)) is None


def test_finished_downloads_are_not_in_flight(store):
    job_in(store, "complete", error="dry run - not organized")
    job_in(store, "organized")
    job_in(store, "failed", error="the peer refused")
    job_in(store, "cancelled")
    assert run(store.in_flight_job("rel-1")) is None


def test_one_download_of_a_release_at_a_time_and_the_lock_goes_after():
    order = []

    async def one(name, release="rel-1"):
        async with release_lock(release):
            order.append(f"{name} in")
            await asyncio.sleep(0.01)
            order.append(f"{name} out")

    async def go():
        await asyncio.gather(one("a"), one("b"))
        assert store_index._RELEASE_LOCKS == {}, "a lock nobody holds or waits for is dropped"
        await asyncio.gather(one("c"), one("d", release="rel-2"))

    run(go())
    assert order[:4] == ["a in", "a out", "b in", "b out"]
    #? another release never waits
    assert order[4:6] == ["c in", "d in"]


def test_no_release_id_is_no_lock():
    async def go():
        async with release_lock(None):
            async with release_lock(""):
                return store_index._RELEASE_LOCKS

    assert run(go()) == {}


# ================================================================ Find

class FakeSlskd:
    def __init__(self, transfers=None, enqueue_delay=0.0):
        self.searched, self.asked = [], []
        self.transfers = transfers or []
        self.enqueue_delay = enqueue_delay
        #? how many enqueues were inside slskd at once, at most
        self.inside = self.most_inside = 0

    async def search_all(self, queries, **kwargs):
        self.searched.append(list(queries))
        return []

    async def get_downloads(self, usernames=()):
        return [t for t in self.transfers if t["username"] in set(usernames)]

    async def enqueue(self, username, files):
        self.asked.append(username)
        self.inside += 1
        self.most_inside = max(self.most_inside, self.inside)
        await asyncio.sleep(self.enqueue_delay)
        self.inside -= 1
        return True, ""

    async def cancel_download(self, *a, **k):
        return True


def request_for(store, slskd):
    return SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(
        store=store, slskd_client=slskd, musicbrainz_client=None)))


def find(store, slskd, **fields):
    body = routes.FindCandidatesRequest(**{**RELEASE, **fields})
    return run(routes.find_candidates(request_for(store, slskd), body))


def test_the_browser_sends_the_release_group_and_the_request_keeps_it():
    assert routes.FindCandidatesRequest(**RELEASE).model_dump()["release_group_mbid"] == "grp-1"


def test_find_keeps_what_names_an_editions_folder():
    """Without these, where a download would be filed is worked out for the wrong folder."""
    sent = {**RELEASE, "disambiguation": "2014 vinyl", "media_format": '12" Vinyl', "country": "GB",
            "catalog_number": "828 553-1"}
    kept = routes.FindCandidatesRequest(**sent).model_dump()
    assert [kept[k] for k in ("disambiguation", "media_format", "country", "catalog_number")] == \
        ["2014 vinyl", '12" Vinyl', "GB", "828 553-1"]


def test_find_does_not_search_for_a_pressing_held_complete(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    run(index_folder(store, str(tmp_path), on_disk(tmp_path)))
    run(index_folder(store, str(tmp_path), on_disk(tmp_path, "Portishead/Dummy (1994) [2014 vinyl]", release="rel-vinyl")))
    slskd = FakeSlskd()

    answer = find(store, slskd)

    assert slskd.searched == []
    assert (answer["held"]["path"], answer["held"]["complete"], answer["candidates"]) == (DUMMY, True, [])
    assert [p["path"] for p in answer["other_pressings"]] == ["Portishead/Dummy (1994) [2014 vinyl]"]
    assert (answer["query"], answer["queries"], answer["response_count"]) == ("", [], 0)


def test_find_does_not_search_for_a_pressing_already_downloading(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    job_id = job_in(store, "downloading")
    slskd = FakeSlskd(transfers=[{"username": "bob", "directories": [{"files": [
        {"filename": "share\\Dummy\\01.flac", "state": "Completed, Succeeded", "percentComplete": 100},
        {"filename": "share\\Dummy\\02.flac", "state": "InProgress", "percentComplete": 40}]}]}])
    answer = find(store, slskd)

    assert slskd.searched == []
    assert answer["downloading"] == {"job_id": job_id, "status": "downloading", "username": "bob",
                                     "files": 2, "done_files": 1}
    assert answer["candidates"] == [] and answer["held"] is None


def test_find_searches_a_pressing_held_in_part_and_says_so(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    run(index_folder(store, str(tmp_path), on_disk(tmp_path, tracks=1)))
    slskd = FakeSlskd()

    answer = find(store, slskd)

    assert slskd.searched == [["Portishead Dummy"]]
    assert (answer["held"]["track_count"], answer["held"]["expected_tracks"], answer["held"]["complete"]) == (1, 2, False)
    #? held where filing would put it, so a download fills it in
    assert (answer["held"]["fills_gaps"], answer["held"]["filed_to"]) == (True, DUMMY)
    assert answer["downloading"] is None and answer["other_pressings"] == []


def test_a_part_held_in_a_folder_filing_wouldnt_choose_is_not_filled_in(tmp_path, store, monkeypatch):
    """Picard's Artist/Album: filing makes Dummy (1994) beside it, every track and all."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    run(index_folder(store, str(tmp_path), on_disk(tmp_path, "Portishead/Dummy", tracks=1)))

    held = find(store, FakeSlskd())["held"]

    assert (held["complete"], held["fills_gaps"], held["filed_to"]) == (False, False, DUMMY)


def test_asking_where_a_download_would_go_says_nothing_in_the_log(tmp_path, store, monkeypatch, caplog):
    """Dummy (1994) holds another pressing, so filing would escalate - but nothing is being filed."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    on_disk(tmp_path, release="another-pressing")
    run(index_folder(store, str(tmp_path), on_disk(tmp_path, "Portishead/Dummy", tracks=1)))

    with caplog.at_level(logging.INFO):
        held = find(store, FakeSlskd())["held"]

    assert held["fills_gaps"] is False and held["filed_to"] not in (None, DUMMY, "Portishead/Dummy")
    assert "filing this edition separately" not in caplog.text


def test_where_filing_would_go_follows_the_edition(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    vinyl = on_disk(tmp_path, "Portishead/Dummy (1994) [2014 vinyl]", tracks=1)
    run(index_folder(store, str(tmp_path), vinyl))

    held = find(store, FakeSlskd(), disambiguation="2014 vinyl")["held"]
    assert (held["fills_gaps"], held["filed_to"]) == (True, "Portishead/Dummy (1994) [2014 vinyl]")


def test_find_without_a_release_id_is_not_checked_at_all(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    job_in(store, "downloading", release_mbid=None)
    slskd = FakeSlskd()
    answer = find(store, slskd, release_mbid=None, tracks=[])
    assert slskd.searched == [["Portishead Dummy"]] and answer["downloading"] is None


def test_a_download_of_part_of_a_pressing_is_a_note_and_the_rest_can_be_had(tmp_path, store, monkeypatch):
    """bob's lone disc folder, one file of two: it will never bring the rest."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    job_in(store, "downloading", files=1)
    slskd = FakeSlskd()

    answer = find(store, slskd)
    assert slskd.searched == [["Portishead Dummy"]]
    assert answer["downloading"] is None
    assert (answer["downloading_part"]["username"], answer["downloading_part"]["files"]) == ("bob", 1)

    run(routes.enqueue(request_for(store, slskd), enqueue_body("sue")))
    assert slskd.asked == ["sue"]


def test_a_download_of_every_audio_track_is_the_whole_pressing(tmp_path, store, monkeypatch):
    """Two files for a CD of two and a DVD: nothing of it will ever be a third file."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    job_in(store, "downloading", files=2, release=with_video(2, 1))
    slskd = FakeSlskd()

    answer = find(store, slskd, tracks=with_video(2, 1)["tracks"])
    assert slskd.searched == [] and answer["downloading"]["files"] == 2


def test_a_broken_index_never_stops_the_search(tmp_path, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    class Broken:
        available = True

        def fail(self, *a, **k):
            raise RuntimeError("the database is on fire")

        index_present = index_pressings = in_flight_job = index_gone = fail

        async def peer_speeds(self, names):
            return {}

    slskd = FakeSlskd()
    answer = find(Broken(), slskd)
    assert slskd.searched == [["Portishead Dummy"]] and answer["held"] is None


# ================================================================ /enqueue

def enqueue_body(user="bob", release=None, files=2):
    """A download of the whole pressing (a file per track) - or of `files` of them."""
    return routes.EnqueueRequest(username=user, files=[{"filename": f"{user}\\0{n}.flac", "size": 1}
                                                       for n in range(1, files + 1)],
                                 directory=f"{user}\\Dummy", release=release or RELEASE)


def test_enqueue_refuses_a_pressing_held_complete(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    run(index_folder(store, str(tmp_path), on_disk(tmp_path)))
    slskd = FakeSlskd()

    with pytest.raises(HTTPException) as refused:
        run(routes.enqueue(request_for(store, slskd), enqueue_body()))

    assert (refused.value.status_code, refused.value.detail) == (409, f"already in your library: {DUMMY}")
    assert slskd.asked == []


def test_enqueue_refuses_a_pressing_already_downloading(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    job_in(store, "queued", user="alice")
    slskd = FakeSlskd()

    with pytest.raises(HTTPException) as refused:
        run(routes.enqueue(request_for(store, slskd), enqueue_body()))

    assert (refused.value.status_code, refused.value.detail) == (409, "already downloading from alice")
    assert slskd.asked == []


def test_enqueue_says_a_download_being_filed_is_being_filed(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    job_in(store, "organizing", user="alice")

    with pytest.raises(HTTPException) as refused:
        run(routes.enqueue(request_for(store, FakeSlskd()), enqueue_body()))
    assert refused.value.detail == "already downloaded from alice, and being filed now"


def test_enqueue_still_takes_a_pressing_held_in_part(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    run(index_folder(store, str(tmp_path), on_disk(tmp_path, tracks=1)))
    assert run(routes.enqueue(request_for(store, FakeSlskd()), enqueue_body()))["job_id"]


def test_two_enqueues_of_one_release_at_once_reach_slskd_once(tmp_path, store, monkeypatch):
    """Two tabs, or a double click: the second finds the first's job, not a gap before it."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    slskd = FakeSlskd(enqueue_delay=0.05)
    request = request_for(store, slskd)

    async def both():
        return await asyncio.gather(routes.enqueue(request, enqueue_body("bob")),
                                    routes.enqueue(request, enqueue_body("sue")), return_exceptions=True)

    first, second = run(both())

    assert slskd.asked == ["bob"]
    assert first["job_id"]
    assert isinstance(second, HTTPException) and second.detail == "already downloading from bob"


def test_two_enqueues_without_a_release_id_are_not_held_up(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    slskd = FakeSlskd(enqueue_delay=0.01)
    request = request_for(store, slskd)
    loose = {**RELEASE, "release_mbid": None}

    async def both():
        return await asyncio.gather(routes.enqueue(request, enqueue_body("bob", loose)),
                                    routes.enqueue(request, enqueue_body("sue", loose)))

    run(both())
    assert sorted(slskd.asked) == ["bob", "sue"]
    #? side by side, not one after the other - nothing locks a release with no id
    assert slskd.most_inside == 2


# ================================================================ retries

def failed_job(store, alternatives=()):
    async def go():
        job_id = await store.create_job("first", "share\\Dummy", [{"filename": "share\\Dummy\\01.flac", "size": 1}],
                                        RELEASE, list(alternatives))
        await store.update_status(job_id, "failed", "the peer refused")
        return await store.get_job(job_id)
    return run(go())


ALT = {"username": "next", "directory": "share\\Dummy", "files": [{"filename": "share\\Dummy\\01.flac", "size": 1}]}


def test_the_next_peer_is_not_asked_for_a_release_filed_complete_since(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    job = failed_job(store, [ALT])
    run(index_folder(store, str(tmp_path), on_disk(tmp_path)))
    slskd = FakeSlskd()

    outcome = run(retry_next_peer(slskd, store, job))

    assert outcome == {"moved": False, "username": None, "directory": None, "left": 1,
                       "problem": f"already in your library: {DUMMY}"}
    assert slskd.asked == []
    assert run(store.get_job(job["id"]))["status"] == "failed"


def test_the_next_peer_is_not_asked_while_another_job_brings_it_in(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    job = failed_job(store, [ALT])
    job_in(store, "downloading", user="alice")
    slskd = FakeSlskd()

    outcome = run(retry_next_peer(slskd, store, job))
    assert (outcome["moved"], outcome["problem"]) == (False, "already downloading from alice")
    assert slskd.asked == []


def test_the_next_peer_is_asked_when_nothing_else_has_it(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    slskd = FakeSlskd()
    assert run(retry_next_peer(slskd, store, failed_job(store, [ALT])))["moved"]
    assert slskd.asked == ["next"]


def test_the_same_peer_is_not_asked_again_for_a_release_filed_since(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(poller, "remove_incomplete_downloads", lambda *a, **k: {"removed": [], "skipped": [], "problem": None})
    job = failed_job(store)
    run(index_folder(store, str(tmp_path), on_disk(tmp_path)))
    slskd = FakeSlskd()

    outcome = run(retry_same_peer(slskd, store, job))

    assert outcome == {"retried": False, "username": "first", "files": 0,
                       "problem": f"already in your library: {DUMMY}"}
    assert slskd.asked == []


def test_a_retry_of_a_job_that_moved_on_meanwhile_asks_nobody(tmp_path, store, monkeypatch):
    """The route read the job failed; by the time the lock was had, another retry had moved it."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    stale = failed_job(store, [ALT])
    run(store.move_to_peer(stale["id"], "next", "share\\Dummy", ALT["files"], [{"username": "next"}]))
    slskd = FakeSlskd()

    moved = run(retry_next_peer(slskd, store, stale))
    again = run(retry_same_peer(slskd, store, stale))

    assert (moved["moved"], moved["problem"]) == (False, poller.MOVED_ON)
    assert (again["retried"], again["problem"]) == (False, poller.MOVED_ON)
    assert slskd.asked == []
    assert run(store.get_job(stale["id"]))["username"] == "next", "left where the other retry put it"


def test_a_retry_goes_on_from_the_job_as_it_is_now(tmp_path, store, monkeypatch):
    """A retry refused by two peers meanwhile left the job failed, with them recorded as tried."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(poller, "remove_incomplete_downloads", lambda *a, **k: {"removed": [], "skipped": [], "problem": None})
    stale = failed_job(store, [{**ALT, "username": u} for u in ("a", "b", "c")])

    class Refusing(FakeSlskd):
        async def enqueue(self, username, files):
            self.asked.append(username)
            return (False, f"{username} is offline") if username in ("a", "b") else (True, "")

    #? what that other retry left: still failed, a and b tried
    run(store.record_tried(stale["id"], stale["tried"] + [{"username": "a"}, {"username": "b"}]))

    slskd = Refusing()
    outcome = run(retry_next_peer(slskd, store, stale))
    assert slskd.asked == ["c"], "a and b were asked already - the fresh row says so"
    assert outcome["moved"] and outcome["username"] == "c"


def test_two_retries_of_one_job_at_once_reach_slskd_once(tmp_path, store, monkeypatch):
    """Auto-retry holding the lock while slskd connects, and a click on the still-failed row."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(poller, "remove_incomplete_downloads", lambda *a, **k: {"removed": [], "skipped": [], "problem": None})
    job = failed_job(store, [ALT, {**ALT, "username": "spare"}])
    slskd = FakeSlskd(enqueue_delay=0.05)

    async def both():
        return await asyncio.gather(retry_next_peer(slskd, store, job), retry_same_peer(slskd, store, job))

    moved, same = run(both())

    assert slskd.asked == ["next"]
    assert moved["moved"] and (same["retried"], same["problem"]) == (False, poller.MOVED_ON)
    assert run(store.get_job(job["id"]))["username"] == "next"


def test_two_retries_of_a_job_with_no_release_id_reach_slskd_once(tmp_path, store, monkeypatch):
    """No release to lock on, so the job is locked on: the re-read then stops the second."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(poller, "remove_incomplete_downloads", lambda *a, **k: {"removed": [], "skipped": [], "problem": None})

    async def go():
        job_id = await store.create_job("first", "share\\Dummy", [{"filename": "share\\Dummy\\01.flac", "size": 1}],
                                        {**RELEASE, "release_mbid": None, "tracks": []}, [ALT])
        await store.update_status(job_id, "failed", "the peer refused")
        return await store.get_job(job_id)
    job = run(go())
    slskd = FakeSlskd(enqueue_delay=0.05)

    async def both():
        return await asyncio.gather(retry_next_peer(slskd, store, job), retry_same_peer(slskd, store, job))

    moved, same = run(both())

    assert slskd.asked == ["next"]
    assert moved["moved"] and (same["retried"], same["problem"]) == (False, poller.MOVED_ON)
    assert store_index._RELEASE_LOCKS == {}


def test_a_retry_of_a_job_cleared_meanwhile_asks_nobody(tmp_path, store, monkeypatch):
    """"Clear finished" while the retry waited: slskd would fetch an album no job is watching."""
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    stale = failed_job(store, [ALT])
    run(store.delete_jobs(("failed",)))
    slskd = FakeSlskd()

    moved = run(retry_next_peer(slskd, store, stale))
    again = run(retry_same_peer(slskd, store, stale))

    assert (moved["moved"], moved["problem"]) == (False, poller.CLEARED)
    assert (again["retried"], again["problem"]) == (False, poller.CLEARED)
    assert slskd.asked == []


def test_auto_retry_says_nothing_when_a_click_got_there_first(tmp_path, store, monkeypatch, caplog):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "on")
    stale = failed_job(store, [ALT])
    run(store.move_to_peer(stale["id"], "next", "share\\Dummy", ALT["files"], [{"username": "next"}]))

    with caplog.at_level(logging.WARNING):
        run(poller._auto_retry(FakeSlskd(), store, stale))

    assert "couldn't move" not in caplog.text


def test_auto_retry_leaves_a_release_filed_since_alone(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "AUTO_RETRY_PEER", "on")
    async def go():
        job_id = await store.create_job("first", "share\\Dummy", [{"filename": "share\\Dummy\\01.flac", "size": 1}],
                                        RELEASE, [ALT])
        return job_id
    job_id = run(go())
    run(index_folder(store, str(tmp_path), on_disk(tmp_path)))
    slskd = FakeSlskd(transfers=[{"username": "first", "directories": [{"files": [
        {"filename": "share\\Dummy\\01.flac", "state": "Completed, Rejected", "percentComplete": 0}]}]}])

    run(poll_downloads_once(slskd, store, {}))

    assert slskd.asked == []
    assert run(store.get_job(job_id))["status"] == "failed"


# ================================================================ the writers

def downloads_with_flacs(tmp_path):
    folder = tmp_path / "downloads" / "album"
    for n in (1, 2):
        write_flac(folder / f"0{n}.flac", title=f"Track {n}", tracknumber=str(n))
    return tmp_path / "downloads"


def filed_job(store):
    files = [{"filename": "share/album/01.flac", "size": 1}, {"filename": "share/album/02.flac", "size": 1}]
    release = {"artist": "Boards of Canada", "album": "Music Has the Right to Children", "year": "1998",
               "release_mbid": "mb-1", "tracks": []}
    return run(store.create_job("bob", "share/album", files, release))


ALL_DONE = [{"username": "bob", "directories": [{"files": [
    {"filename": "share/album/01.flac", "state": "Completed, Succeeded", "percentComplete": 100},
    {"filename": "share/album/02.flac", "state": "Completed, Succeeded", "percentComplete": 100}]}]}]


def test_filing_indexes_the_album(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(downloads_with_flacs(tmp_path)))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    filed_job(store)

    run(poll_downloads_once(FakeSlskd(transfers=ALL_DONE), store, {}))

    [row] = rows(store)
    assert (row["path"], row["release_mbid"], row["track_count"], row["state"]) == \
        ("Boards of Canada/Music Has the Right to Children (1998)", "mb-1", 2, "present")
    #? and the next Find of it knows
    assert run(held_copy(store, str(tmp_path / "music"), "mb-1", {"tracks": []}))["complete"]


def test_a_dry_run_indexes_nothing(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(downloads_with_flacs(tmp_path)))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "dry_run")
    filed_job(store)
    run(poll_downloads_once(FakeSlskd(transfers=ALL_DONE), store, {}))
    assert rows(store) == []


def test_filing_that_partly_failed_still_indexes_what_landed(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    landed = on_disk(tmp_path, tracks=1)

    async def organize(job, download_root, library_root, mode, on_plan=None):
        return {"organized": 1, "skipped": 0, "failed": 1, "dry_run": False, "mode": mode,
                "plan": {"album_dir": str(landed)}}

    monkeypatch.setattr(poller, "organize_job", organize)
    job_id = filed_job(store)
    run(poll_downloads_once(FakeSlskd(transfers=ALL_DONE), store, {}))

    assert run(store.get_job(job_id))["error"] == "1 file(s) failed to organize"
    assert [r["path"] for r in rows(store, state="present")] == [DUMMY]


def client_for(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "0")
    app = FastAPI()
    app.state.store = store
    app.include_router(library_routes.router, prefix="/deadwax/library")
    return TestClient(app)


def test_a_real_scan_reconciles_and_a_snapshot_does_not(tmp_path, store, monkeypatch):
    directory = on_disk(tmp_path)
    client = client_for(tmp_path, store, monkeypatch)

    client.get("/deadwax/library/albums")
    [indexed] = rows(store)
    assert (indexed["path"], indexed["state"]) == (DUMMY, "present")

    #? the index now disagrees with the saved scan a snapshot answers from - a snapshot fed to
    #? the index would bring Dummy's row straight back
    run(store.index_gone(str(tmp_path), DUMMY, "missing"))
    client.get("/deadwax/library/albums", params={"snapshot": "true"})
    assert [(r["id"], r["state"]) for r in rows(store)] == [(indexed["id"], "missing")], "a snapshot is the last scan"

    #? a real scan is the disk: Dummy is there, so its own row comes back
    client.get("/deadwax/library/albums")
    assert [(r["id"], r["state"]) for r in rows(store)] == [(indexed["id"], "present")]

    #? ...and one that no longer finds it marks it missing, and records what it did find
    shutil.rmtree(directory)
    on_disk(tmp_path, "Portishead/Third (2008)", release="rel-3")
    client.get("/deadwax/library/albums")
    assert [(r["path"], r["state"]) for r in rows(store)] == [(DUMMY, "missing"), ("Portishead/Third (2008)", "present")]


def test_a_scan_listing_an_album_deleted_since_leaves_its_tombstone(tmp_path, store):
    """Through the real look at the disk: the walk listed Dummy, deadwax deleted it, then the scan landed."""
    root = str(tmp_path)
    directory = on_disk(tmp_path)
    run(index_folder(store, root, directory))
    shutil.rmtree(directory)
    run(store_index.mark_deleted(store, root, DUMMY))

    run(store_index.reconcile_scan(store, root, [album()]))

    assert [(r["path"], r["state"]) for r in rows(store)] == [(DUMMY, "deleted")]


def test_an_album_filed_while_the_scan_went_past_is_not_marked_missing(tmp_path, store):
    """The scan began before the poller filed Dummy, so it never saw it - but Dummy is there."""
    root = str(tmp_path)
    run(index_folder(store, root, on_disk(tmp_path)))
    on_disk(tmp_path, "Portishead/Third (2008)", release="rel-3")

    run(store_index.reconcile_scan(store, root, [album(path="Portishead/Third (2008)", release="rel-3")]))

    assert [(r["path"], r["state"]) for r in rows(store)] == [(DUMMY, "present"), ("Portishead/Third (2008)", "present")]


def test_a_folder_being_filed_is_never_paired_with_a_tombstone(tmp_path, store):
    """
    A scan landing mid-copy finds Dummy with no live row yet. With the share that held the release
    unmounted, pairing by release would hand the fresh download the share's id.
    """
    root = str(tmp_path)
    share = run(store.index_upsert(root, album(path="Share/Dummy")))
    run(store.index_gone(root, "Share/Dummy", "missing"))
    on_disk(tmp_path)

    key = store_index.filing_started(root, tmp_path / DUMMY)
    try:
        run(store_index.reconcile_scan(store, root, [album()]))
    finally:
        store_index.filing_finished(key)

    [filed] = rows(store, state="present")
    assert filed["id"] != share and rows(store, id=share)[0]["state"] == "missing"
    assert not store_index.being_filed(DUMMY)


def test_the_poller_marks_the_folder_being_filed_until_it_is_indexed(tmp_path, store, monkeypatch):
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    seen = []

    async def organize(job, download_root, library_root, mode, on_plan=None):
        landed = on_disk(tmp_path)
        on_plan({"album_dir": str(landed)})
        seen.append(("copying", store_index.being_filed(DUMMY)))
        if job["album"] == "broken":
            raise OSError("disk full")
        return {"organized": 2, "skipped": 0, "failed": 0, "dry_run": False, "mode": mode,
                "plan": {"album_dir": str(landed)}}

    indexing = poller.index_folder

    async def index_and_look(*args):
        seen.append(("indexing", store_index.being_filed(DUMMY)))
        return await indexing(*args)

    monkeypatch.setattr(poller, "organize_job", organize)
    monkeypatch.setattr(poller, "index_folder", index_and_look)
    for album_name in ("Dummy", "broken"):
        run(poller._organize_if_enabled({"id": 1, "artist": "Portishead", "album": album_name}, store))
        assert not store_index.being_filed(DUMMY), f"cleared after {album_name}"

    assert seen == [("copying", True), ("indexing", True), ("copying", True)]


def test_the_index_keeps_the_folders_own_edition_not_the_scans_standard(tmp_path, store, monkeypatch):
    on_disk(tmp_path)
    on_disk(tmp_path, "Portishead/Dummy (1994) [2014 vinyl]", release="rel-vinyl")
    client = client_for(tmp_path, store, monkeypatch)

    scanned = {a["path"]: a["edition"] for a in client.get("/deadwax/library/albums").json()["albums"]}
    assert scanned[DUMMY] == "Standard", "the scan's display label, beside another edition"

    assert {r["path"]: r["edition"] for r in rows(store)} == {DUMMY: "", "Portishead/Dummy (1994) [2014 vinyl]": "2014 vinyl"}


def test_applying_a_release_that_renames_the_folder_keeps_the_row(tmp_path, store, monkeypatch):
    from tests.test_retag import RELEASE as SLOW_RUSH, seed

    seed(tmp_path)
    client = client_for(tmp_path, store, monkeypatch)
    client.get("/deadwax/library/albums")
    [before] = rows(store)

    response = client.post("/deadwax/library/retag/apply",
                           json={"album_path": "Tame Impala/The Slow Rush (2020)", "release": SLOW_RUSH})
    assert response.status_code == 200 and response.json()["results"]["moved_to"]

    [after] = rows(store)
    assert after["id"] == before["id"]
    assert (after["path"], after["release_mbid"], after["state"]) == \
        ("Tame Impala/The Slow Rush (2020) [Deluxe edition]", "mbid-deluxe", "present")


def test_during_the_pause_before_the_rename_the_new_release_is_already_held(tmp_path, store, monkeypatch):
    """Up to 90s with Navidrome: long enough to Find and download the pressing just applied again."""
    from tests.test_retag import RELEASE as SLOW_RUSH, seed

    seed(tmp_path)
    client = client_for(tmp_path, store, monkeypatch)
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "5")
    client.get("/deadwax/library/albums")
    [before] = rows(store)
    during = []

    async def pause(seconds):
        held = await held_copy(store, str(tmp_path), "mbid-deluxe", SLOW_RUSH)
        during.append((held["path"], held["complete"]) if held else None)

    monkeypatch.setattr(library_routes.asyncio, "sleep", pause)
    response = client.post("/deadwax/library/retag/apply",
                           json={"album_path": "Tame Impala/The Slow Rush (2020)", "release": SLOW_RUSH})

    assert response.json()["results"]["moved_to"]
    assert during == [("Tame Impala/The Slow Rush (2020)", True)]
    [after] = rows(store)
    assert (after["id"], after["path"]) == (before["id"], "Tame Impala/The Slow Rush (2020) [Deluxe edition]")


def test_applying_a_release_in_place_reindexes_it(tmp_path, store, monkeypatch):
    from tests.test_retag import RELEASE as SLOW_RUSH, seed

    seed(tmp_path, folder="The Slow Rush (2020) [Deluxe edition]")
    client = client_for(tmp_path, store, monkeypatch)
    client.get("/deadwax/library/albums")

    client.post("/deadwax/library/retag/apply",
                json={"album_path": "Tame Impala/The Slow Rush (2020) [Deluxe edition]", "release": SLOW_RUSH})
    assert rows(store)[0]["release_mbid"] == "mbid-deluxe"


def test_merging_a_disc_folder_leaves_a_tombstone_pointing_at_the_album(tmp_path, store, monkeypatch):
    from tests.test_split_discs import RELEASE as OK_COMPUTER, disc_folder

    disc_folder(tmp_path, "OK Computer (1997)", 1, ["Airbag", "Paranoid Android"])
    disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"])
    client = client_for(tmp_path, store, monkeypatch)
    client.get("/deadwax/library/albums")
    ids = {r["path"]: r["id"] for r in rows(store)}

    response = client.post("/deadwax/library/retag/apply",
                           json={"album_path": "Radiohead/OK Computer (Disc 2)", "release": OK_COMPUTER})
    assert response.json()["results"].get("merged")

    source = rows(store, id=ids["Radiohead/OK Computer (Disc 2)"])[0]
    target = rows(store, id=ids["Radiohead/OK Computer (1997)"])[0]
    assert (source["state"], source["merged_into"]) == ("merged", target["id"])
    assert (target["state"], target["track_count"]) == ("present", 4)


def test_refiling_an_artist_keeps_each_albums_row(tmp_path, store, monkeypatch):
    from tests.test_artist_refile import album as refile_album

    refile_album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    clear_scan_cache()

    class MusicBrainz:
        async def get_artist(self, mbid):
            return {"id": mbid, "name": "Ye", "aliases": []}

    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(musicbrainz_client=MusicBrainz(), store=store)))
    body = library_routes.ArtistRefileRequest(artist="Kanye West")
    run(library_routes.artist_refile_preview(request, body))
    [before] = rows(store)

    run(library_routes.artist_refile_apply(request, body))

    [after] = rows(store)
    assert (after["id"], after["path"], after["artist"]) == (before["id"], "Ye/Donda (2021)", "Ye")


def test_deleting_an_album_leaves_a_tombstone(tmp_path, store, monkeypatch):
    on_disk(tmp_path)
    client = client_for(tmp_path, store, monkeypatch)
    client.get("/deadwax/library/albums")

    assert client.post("/deadwax/library/delete", json={"album_path": DUMMY}).status_code == 200

    [row] = rows(store)
    assert (row["path"], row["state"]) == (DUMMY, "deleted") and row["gone_at"]


def test_editing_tags_by_hand_reindexes_the_album(tmp_path, store, monkeypatch):
    on_disk(tmp_path)
    client = client_for(tmp_path, store, monkeypatch)
    client.get("/deadwax/library/albums")

    edits = [{"filename": f"0{n} - Track {n}.flac", "tags": {"album": "Dummy (Remastered)"}} for n in (1, 2)]
    assert client.post("/deadwax/library/tags/apply", json={"album_path": DUMMY, "edits": edits}).status_code == 200

    assert rows(store)[0]["album"] == "Dummy (Remastered)"


# ================================================================ a relative LIBRARY_PATH

def test_nothing_that_climbs_out_of_the_library_is_inside_it():
    assert library_relative("/music", "/music/../etc/passwd") is None
    assert library_relative("music", "music/../etc") is None
    assert library_relative("/music", "../etc") is None


def test_paths_are_made_relative_to_the_library_however_they_arrive(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    #? what the writers hand over with a relative root: the root joined on, and still relative
    assert library_relative("music", "music/Portishead/Dummy (1994)") == "Portishead/Dummy (1994)"
    #? what the routes hand over: already relative to the library
    assert library_relative("music", "Portishead/Dummy (1994)") == "Portishead/Dummy (1994)"
    #? absolute, against a relative root
    assert library_relative("music", str(tmp_path / "music" / "Portishead")) == "Portishead"
    assert library_relative("music", str(tmp_path / "elsewhere")) is None
    #? and with an absolute root as ever
    assert library_relative(str(tmp_path), str(tmp_path / "A" / "B")) == "A/B"
    assert library_relative(str(tmp_path), "/somewhere/else") is None
    assert library_relative(str(tmp_path), "../outside") is None


def test_a_folder_known_under_two_spellings_keeps_one_row(tmp_path, store):
    """
    deadwax filed Portishead/..., the disk calls it portishead/... (a case-insensitive disk opens
    either). Opening the old spelling proves nothing, so the old row went and the folder, found
    under the new one, took its id back - not a second live row for one folder, for good.
    """
    if not case_insensitive(tmp_path):
        pytest.skip("needs a case-insensitive disk")
    root = str(tmp_path)
    first = run(store.index_upsert(root, album()))
    on_disk(tmp_path, "portishead/Dummy (1994)")

    run(store_index.reconcile_scan(store, root, [album(path="portishead/Dummy (1994)")]))

    assert [(r["id"], r["path"]) for r in rows(store, state="present")] == [(first, "portishead/Dummy (1994)")]


def test_a_folder_named_in_another_case_is_recorded_as_the_disk_spells_it(tmp_path, store):
    if not case_insensitive(tmp_path):
        pytest.skip("needs a case-insensitive disk")
    on_disk(tmp_path, "portishead/Dummy (1994)")

    run(index_folder(store, str(tmp_path), tmp_path / DUMMY))

    assert [r["path"] for r in rows(store)] == ["portishead/Dummy (1994)"]


def test_filing_and_seeding_index_the_right_paths_under_a_relative_library_path(tmp_path, store, monkeypatch):
    from src.organizer import resolve_album_dir

    monkeypatch.chdir(tmp_path)
    on_disk(tmp_path / "music")
    album_dir, _ = resolve_album_dir("music", RELEASE)
    assert str(album_dir) == f"music/{DUMMY}"

    assert run(index_folder(store, "music", album_dir))
    assert [(r["root"], r["path"]) for r in rows(store)] == [("music", DUMMY)]

    other = JobStore(str(tmp_path / "other.db"))
    other.init()
    run(other.save_library_cache("music", [(f"music/{DUMMY}", 1.0, album())], [], SCAN_FORMAT))
    run(seed_from_saved_scan(other, "music"))
    assert [r["path"] for r in rows(other)] == [DUMMY]
