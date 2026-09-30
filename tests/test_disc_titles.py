"""
Each disc's own title (v1.1.0): "Live at Wembley 1974" on a box set's fourth disc, not just "Disc 4".

MusicBrainz calls it the medium title, Picard writes it as DISCSUBTITLE and Navidrome reads it. It
now goes the whole way: carried per track in a download's or an apply's payload, written as the
`discsubtitle` tag, read back by the retag preview so a right album still says "nothing to
change", read by the scan into one map per album, and editable by hand.

Real files throughout, as in test_library_cache.py. The m4a is a real one too, 778 bytes of
silence made once with ffmpeg and kept below as base64: Easy MP4 has no key for a disc title of its
own, and only a real file shows whether the one taught to it (src/tagkeys.py) reads and writes.
"""

import asyncio
import base64

import pytest

from src import library
from src.library import SCAN_FORMAT, compact_for_wire, drain_cache_changes, scan_library, seed_cache
from src.organizer import tag_values, write_tags
from src.retag import execute_retag, plan_retag, read_current_tags
from src.store import JobStore
from src.tagkeys import easy_file
from src.track_tags import execute_tag_edits, plan_tag_edits
from tests.test_library_cache import write_flac

LIVE = "The Dark Side of the Moon Live at Wembley Empire Pool, London, 1974"

BOX = {
    "album": "The Dark Side of the Moon", "artist": "Pink Floyd", "year": "2023",
    "original_year": "1973", "release_mbid": "mbid-dsotm-box",
    "tracks": [
        {"position": 1, "title": "Speak to Me", "disc": 1, "disc_position": 1,
         "disc_title": "Remastered Original Album"},
        {"position": 2, "title": "Breathe", "disc": 1, "disc_position": 2,
         "disc_title": "Remastered Original Album"},
        {"position": 3, "title": "Speak to Me (live)", "disc": 2, "disc_position": 1, "disc_title": LIVE},
        {"position": 4, "title": "Breathe (live)", "disc": 2, "disc_position": 2, "disc_title": LIVE},
    ],
}

TINY_M4A = base64.b64decode(
    "AAAAHGZ0eXBNNEEgAAACAE00QSBpc29taXNvMgAAAtZtb292AAAAbG12aGQAAAAAAAAAAAAAAAAAAB9AAAABkAAB"
    "AAABAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAACAAACJXRyYWsAAABcdGtoZAAAAAMAAAAAAAAAAAAAAAEAAAAAAAABkAAAAAAAAAAAAAAAAQEA"
    "AAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAACRlZHRzAAAAHGVsc3QAAAAA"
    "AAAAAQAAAZAAAAQAAAEAAAAAAZ1tZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAAB9AAAAFkFXEAAAAAAAtaGRscgAA"
    "AAAAAAAAc291bgAAAAAAAAAAAAAAAFNvdW5kSGFuZGxlcgAAAAFIbWluZgAAABBzbWhkAAAAAAAAAAAAAAAkZGlu"
    "ZgAAABxkcmVmAAAAAAAAAAEAAAAMdXJsIAAAAAEAAAEMc3RibAAAAGpzdHNkAAAAAAAAAAEAAABabXA0YQAAAAAA"
    "AAABAAAAAAAAAAAAAQAQAAAAAB9AAAAAAAA2ZXNkcwAAAAADgICAJQABAASAgIAXQBUAAAAAAB9AAAABZwWAgIAF"
    "FYhW5QAGgICAAQIAAAAgc3R0cwAAAAAAAAACAAAAAQAABAAAAAABAAABkAAAABxzdHNjAAAAAAAAAAEAAAABAAAA"
    "AgAAAAEAAAAUc3RzegAAAAAAAAAEAAAAAgAAABRzdGNvAAAAAAAAAAEAAAMCAAAAGnNncGQBAAAAcm9sbAAAAAIA"
    "AAAB//8AAAAcc2JncAAAAAByb2xsAAAAAQAAAAIAAAABAAAAPXVkdGEAAAA1bWV0YQAAAAAAAAAhaGRscgAAAAAA"
    "AAAAbWRpcmFwcGwAAAAAAAAAAAAAAAAIaWxzdAAAAAhmcmVlAAAAEG1kYXQBGCAHARggBw=="
)


@pytest.fixture(autouse=True)
def fresh_cache():
    library.clear_scan_cache()
    yield
    library.clear_scan_cache()


def run(coroutine):
    return asyncio.run(coroutine)


def box_on_disk(root, titles=True):
    """BOX as a folder of files, tagged the old way: running numbers, no discs, no disc titles."""
    directory = root / "Pink Floyd" / "The Dark Side of the Moon (1973)"
    for track in BOX["tracks"]:
        write_flac(directory / f"{track['position']:02d} - {track['title']}.flac",
                   album=BOX["album"], albumartist="Pink Floyd", artist="Pink Floyd",
                   title=track["title"], tracknumber=str(track["position"]), date="2023",
                   **({"musicbrainz_albumid": BOX["release_mbid"]} if titles else {}))
    return directory


# ---------------------------------------------------------------- what gets written

def test_a_disc_title_is_written_as_discsubtitle():
    values = tag_values(BOX, BOX["tracks"][2])
    assert values["discsubtitle"] == LIVE
    assert (values["discnumber"], values["tracknumber"]) == ("2", "1")


def test_a_single_disc_release_with_a_title_writes_it_too():
    """Unlike the disc NUMBER, which a one-disc release leaves out so "1" doesn't land everywhere."""
    release = {**BOX, "tracks": [{**BOX["tracks"][0], "disc_title": "Remastered Original Album"}]}
    values = tag_values(release, release["tracks"][0])
    assert values["discsubtitle"] == "Remastered Original Album"
    assert "discnumber" not in values


@pytest.mark.parametrize("untitled", [None, ""])
def test_an_untitled_disc_writes_nothing_and_so_leaves_a_title_alone(untitled):
    """MusicBrainz leaves most discs untitled; that is no reason to clear one the file has."""
    track = {**BOX["tracks"][0], "disc_title": untitled}
    assert "discsubtitle" not in tag_values(BOX, track)


def test_a_file_just_given_a_disc_title_reports_no_changes(tmp_path):
    """read_current_tags reads it back, or every titled disc would show a change for ever."""
    path = write_flac(tmp_path / "03.flac", title="placeholder")
    write_tags(path, BOX, BOX["tracks"][2])

    current = read_current_tags(path)
    assert current["discsubtitle"] == LIVE
    desired = tag_values(BOX, BOX["tracks"][2], current)
    assert {k: v for k, v in desired.items() if current.get(k, "") != v} == {}


def test_an_m4a_carries_a_disc_title_where_picard_and_navidrome_look(tmp_path):
    """Easy MP4 knew no disc title: a write was skipped in silence and a read found nothing."""
    from mutagen.mp4 import MP4

    path = tmp_path / "03.m4a"
    path.write_bytes(TINY_M4A)
    write_tags(path, BOX, BOX["tracks"][2])

    assert read_current_tags(path)["discsubtitle"] == LIVE
    assert library.read_track(path)["disc_title"] == LIVE
    #? the atom itself - the name Picard writes and Navidrome's tag mapping reads
    assert [bytes(v).decode() for v in MP4(str(path)).tags["----:com.apple.iTunes:DISCSUBTITLE"]] == [LIVE]
    assert easy_file(path)["discsubtitle"] == [LIVE]


def test_the_download_request_keeps_the_disc_title():
    """The pydantic trap: undeclared, it would vanish between the browser and the organizer."""
    from src.routes.download import EnqueueRelease

    kept = EnqueueRelease(**{**BOX, "tracks": BOX["tracks"]}).model_dump()
    assert kept["tracks"][2]["disc_title"] == LIVE


def test_a_download_is_filed_with_its_disc_titles(tmp_path):
    """The organizer hands write_tags the matched track itself, disc title and all."""
    from src.organizer import execute_plan, plan_organization

    downloads = tmp_path / "downloads" / "DSOTM"
    for track in BOX["tracks"]:
        write_flac(downloads / f"{track['position']:02d} - {track['title']}.flac", title="x")
    job = {"id": 1, "artist": "Pink Floyd", "album": BOX["album"], "username": "bob",
           "directory": "share\\DSOTM", "release": BOX,
           "files": [{"filename": f"share\\DSOTM\\{t['position']:02d} - {t['title']}.flac", "size": 1}
                     for t in BOX["tracks"]]}

    results = execute_plan(plan_organization(job, str(tmp_path / "downloads"), str(tmp_path / "music")),
                           BOX, mode="copy")
    assert results["organized"] == 4
    filed = {p.name: read_current_tags(p).get("discsubtitle") for p in (tmp_path / "music").rglob("*.flac")}
    assert sorted(filed.values()) == sorted(["Remastered Original Album"] * 2 + [LIVE] * 2)


# ---------------------------------------------------------------- applying a release

def test_applying_a_release_writes_its_disc_titles_and_agrees_with_its_preview(tmp_path):
    box_on_disk(tmp_path)
    folder = "Pink Floyd/The Dark Side of the Moon (1973)"

    plan = plan_retag(folder, BOX, str(tmp_path))
    live = next(f for f in plan["files"] if f["track_title"] == "Speak to Me (live)")
    assert live["changes"]["discsubtitle"] == {"from": "", "to": LIVE}

    assert execute_retag(plan, BOX, "apply")["failed"] == 0
    target = tmp_path / (plan.get("target") or folder)
    titles = {p.name: read_current_tags(p).get("discsubtitle") for p in target.glob("*.flac")}
    assert sorted(titles.values()) == sorted([LIVE, LIVE, "Remastered Original Album", "Remastered Original Album"])

    #? the write did what the preview said, so a second look finds nothing to do
    assert plan_retag(str(target.relative_to(tmp_path)), BOX, str(tmp_path))["empty"]


# ---------------------------------------------------------------- the scan

def test_the_scan_gives_each_titled_disc_its_title(tmp_path):
    directory = box_on_disk(tmp_path)
    for track in BOX["tracks"]:
        path = directory / f"{track['position']:02d} - {track['title']}.flac"
        write_tags(path, BOX, track)

    [album] = scan_library(str(tmp_path))["albums"]
    assert album["disc_titles"] == {"1": "Remastered Original Album", "2": LIVE}
    assert album["disc_count"] == 2


def test_a_disc_without_a_title_is_left_out_and_the_commonest_title_wins(tmp_path):
    directory = box_on_disk(tmp_path, titles=False)
    names = sorted(directory.glob("*.flac"))
    #? disc 1 untitled; disc 2 with one file disagreeing, which the track viewer still shows
    for n, path in enumerate(names, start=1):
        write_flac(path, title=f"T{n}", tracknumber="1", discnumber="1" if n <= 2 else "2",
                   **({"discsubtitle": LIVE if n == 3 else "a typo"} if n > 2 else {}))
    write_flac(directory / "05 - Extra.flac", title="Extra", discnumber="2", discsubtitle=LIVE)

    [album] = scan_library(str(tmp_path))["albums"]
    assert album["disc_titles"] == {"2": LIVE}


def test_disc_titles_travel_once_per_album_not_once_per_track(tmp_path):
    directory = box_on_disk(tmp_path)
    for track in BOX["tracks"]:
        write_tags(directory / f"{track['position']:02d} - {track['title']}.flac", BOX, track)

    [album] = compact_for_wire(scan_library(str(tmp_path))["albums"])
    assert album["disc_titles"]["2"] == LIVE
    assert all("disc_title" not in track for track in album["tracks"])


def test_disc_titles_survive_a_restart_with_the_keys_they_had(tmp_path):
    """The saved scan is JSON, so the keys are strings from the start - the same before and after."""
    root = tmp_path / "library"
    directory = box_on_disk(root)
    for track in BOX["tracks"]:
        write_tags(directory / f"{track['position']:02d} - {track['title']}.flac", BOX, track)
    before = scan_library(str(root))["albums"][0]["disc_titles"]

    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    upserts, removals = drain_cache_changes()
    assert run(store.save_library_cache(str(root), upserts, removals, SCAN_FORMAT))
    library.clear_scan_cache()
    assert seed_cache(run(store.load_library_cache(str(root), SCAN_FORMAT))) == 1

    after = scan_library(str(root))
    assert after["cached"] == 1
    assert after["albums"][0]["disc_titles"] == before == {"1": "Remastered Original Album", "2": LIVE}


# ---------------------------------------------------------------- by hand

def test_a_disc_title_can_be_set_and_cleared_by_hand(tmp_path):
    """For the discs MusicBrainz leaves untitled - most of them - and a bootleg's own words."""
    directory = box_on_disk(tmp_path)
    folder = str(directory.relative_to(tmp_path))
    live = [p.name for p in sorted(directory.glob("*.flac"))][2:]

    edits = [{"filename": name, "tags": {"discsubtitle": "Live at Wembley"}} for name in live]
    plan = plan_tag_edits(folder, edits, str(tmp_path))
    assert not plan["problems"] and plan["changed_file_count"] == 2
    assert execute_tag_edits(plan, "apply")["written"] == 2
    assert {read_current_tags(directory / n)["discsubtitle"] for n in live} == {"Live at Wembley"}

    cleared = plan_tag_edits(folder, [{"filename": live[0], "tags": {"discsubtitle": ""}}], str(tmp_path))
    assert execute_tag_edits(cleared, "apply")["written"] == 1
    assert "discsubtitle" not in read_current_tags(directory / live[0])
