"""
Albums stored one folder per disc (v0.9.13).

`Album (Disc 1)` and `Album (Disc 2)` are one release in two places. The library used to call
them two editions, and applying the release to the second was refused because the first had
already taken the folder name. They are recognised now, flagged in the queue, and applying the
release merges them - but only when that is provably the same release and different discs.
"""


from src.library import clear_scan_cache, scan_library, split_disc_folders
from src.metadata_health import inspect_album
from src.retag import execute_retag, plan_retag
from tests.test_retag import write_flac

TRACKS = [
    {"position": 1, "title": "Airbag", "disc": 1, "disc_position": 1, "length_ms": 1000},
    {"position": 2, "title": "Paranoid Android", "disc": 1, "disc_position": 2, "length_ms": 1000},
    {"position": 3, "title": "Lucky", "disc": 2, "disc_position": 1, "length_ms": 1000},
    {"position": 4, "title": "The Tourist", "disc": 2, "disc_position": 2, "length_ms": 1000},
]
RELEASE = {"artist": "Radiohead", "album": "OK Computer", "year": "1997", "original_year": "1997",
           "release_mbid": "okc-2cd", "tracks": TRACKS}


def disc_folder(root, folder, disc, titles, release_id="okc-2cd", names=None):
    directory = root / "Radiohead" / folder
    for n, title in enumerate(titles, start=1):
        name = (names or {}).get(title, f"{disc}-{n:02d} {title}.flac")
        write_flac(directory / name, album="OK Computer", albumartist="Radiohead", artist="Radiohead",
                   title=title, tracknumber=str(n), discnumber=str(disc), date="1997",
                   musicbrainz_albumid=release_id)
    return directory


def scan(root):
    clear_scan_cache()
    return {a["path"]: a for a in scan_library(str(root))["albums"]}


def test_disc_folders_of_one_release_are_discs_not_editions(tmp_path):
    disc_folder(tmp_path, "OK Computer (Disc 1)", 1, ["Airbag", "Paranoid Android"])
    disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"])

    albums = scan(tmp_path)
    one, two = albums["Radiohead/OK Computer (Disc 1)"], albums["Radiohead/OK Computer (Disc 2)"]

    assert (one["disc_label"], two["disc_label"]) == ("Disc 1", "Disc 2")
    #? not an edition label - the editor seeds its edition field from that, and "Disc 2" there
    #? would file the merged album as `OK Computer (1997) [Disc 2]`
    assert (one["edition"], two["edition"]) == ("", "")
    assert one["split_discs"] and two["split_discs"]
    assert one["edition_count"] == 1
    assert "split_discs" in inspect_album(two)


def test_two_copies_of_the_same_disc_are_still_two_editions(tmp_path):
    disc_folder(tmp_path, "OK Computer (rip A)", 1, ["Airbag", "Paranoid Android"])
    disc_folder(tmp_path, "OK Computer (rip B)", 1, ["Airbag", "Paranoid Android"])
    albums = scan(tmp_path)
    assert not any(a["split_discs"] for a in albums.values())
    assert {a["edition_count"] for a in albums.values()} == {2}


def test_untagged_discs_are_never_guessed_at():
    group = [{"release_mbid": "x", "discs": []}, {"release_mbid": "x", "discs": [2]}]
    assert split_disc_folders(group) == []


def test_applying_the_release_to_the_second_disc_merges_it(tmp_path):
    disc_folder(tmp_path, "OK Computer (1997)", 1, ["Airbag", "Paranoid Android"])
    source = disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"])
    (source / "folder.jpg").write_bytes(b"art")

    plan = plan_retag("Radiohead/OK Computer (Disc 2)", RELEASE, str(tmp_path))

    assert plan["merge"] and plan["moves"]
    assert plan["merge_detail"]["discs_here"] == [2] and plan["merge_detail"]["discs_there"] == [1]
    #? the folder holds half the release, and that is no longer a warning
    assert not any("this release has" in p for p in plan["problems"])

    results = execute_retag(plan, RELEASE, mode="apply")

    merged = tmp_path / "Radiohead" / "OK Computer (1997)"
    assert results.get("merged") and not source.exists()
    assert sorted(p.name for p in merged.iterdir()) == [
        "1-01 Airbag.flac", "1-02 Paranoid Android.flac", "2-01 Lucky.flac", "2-02 The Tourist.flac",
        "folder.jpg"]


def test_a_file_name_already_taken_there_refuses_the_merge(tmp_path):
    disc_folder(tmp_path, "OK Computer (1997)", 1, ["Airbag", "Paranoid Android"],
                names={"Airbag": "01.flac", "Paranoid Android": "02.flac"})
    disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"],
                names={"Lucky": "01.flac", "The Tourist": "02.flac"})

    plan = plan_retag("Radiohead/OK Computer (Disc 2)", RELEASE, str(tmp_path))

    assert not plan["merge"] and not plan["moves"]
    assert any("already taken there" in p for p in plan["problems"])


def test_another_release_in_that_folder_refuses_the_merge(tmp_path):
    disc_folder(tmp_path, "OK Computer (1997)", 1, ["Airbag", "Paranoid Android"], release_id="okc-other")
    disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"])

    plan = plan_retag("Radiohead/OK Computer (Disc 2)", RELEASE, str(tmp_path))

    assert not plan["merge"]
    assert any("different album or edition" in p for p in plan["problems"])


def test_the_same_disc_already_there_refuses_the_merge(tmp_path):
    disc_folder(tmp_path, "OK Computer (1997)", 2, ["Lucky", "The Tourist"], names={"Lucky": "a.flac", "The Tourist": "b.flac"})
    disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"])

    plan = plan_retag("Radiohead/OK Computer (Disc 2)", RELEASE, str(tmp_path))

    assert not plan["merge"]
    assert any("same disc" in p for p in plan["problems"])


def test_a_same_named_cover_stays_behind_rather_than_overwriting(tmp_path):
    there = disc_folder(tmp_path, "OK Computer (1997)", 1, ["Airbag", "Paranoid Android"])
    (there / "cover.jpg").write_bytes(b"disc one's cover")
    source = disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"])
    (source / "cover.jpg").write_bytes(b"disc two's cover")

    plan = plan_retag("Radiohead/OK Computer (Disc 2)", RELEASE, str(tmp_path))
    assert plan["merge_detail"]["kept_back"] == ["cover.jpg"]
    results = execute_retag(plan, RELEASE, mode="apply")

    assert (there / "cover.jpg").read_bytes() == b"disc one's cover"
    assert (source / "cover.jpg").read_bytes() == b"disc two's cover"
    assert any("kept cover.jpg" in p for p in results["problems"])


def test_no_cover_is_fetched_for_a_folder_about_to_join_one_that_has_it(tmp_path):
    there = disc_folder(tmp_path, "OK Computer (1997)", 1, ["Airbag", "Paranoid Android"])
    (there / "cover.jpg").write_bytes(b"art")
    disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"])

    plan = plan_retag("Radiohead/OK Computer (Disc 2)", RELEASE, str(tmp_path), want_art=True)

    assert plan["merge"] and plan["art"]["action"] == ""


def test_the_merged_into_folder_keeps_its_review_row(tmp_path, monkeypatch):
    """
    Through the real route: the apply passes the folder merged into as where the album went, and
    that folder is still there with its own history - when it was first seen, and what you'd
    accepted about it. A merge used to replace that row with the disc folder's (v1.1.4).
    """
    import asyncio

    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from src.config import Config
    from src.routes import library as route
    from src.store import JobStore

    disc_folder(tmp_path, "OK Computer (1997)", 1, ["Airbag", "Paranoid Android"])
    disc_folder(tmp_path, "OK Computer (Disc 2)", 2, ["Lucky", "The Tourist"])
    store = JobStore(str(tmp_path / "state" / "deadwax.db"))
    store.init()
    there, here = "Radiohead/OK Computer (1997)", "Radiohead/OK Computer (Disc 2)"
    asyncio.run(store.record_albums_seen([{"path": there}, {"path": here}]))
    asyncio.run(store.ignore_album_issues(there, ["no_art"]))
    first_seen = asyncio.run(store.album_reviews())[there]["first_seen"]

    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "RETAG_RENAME_WAIT", "0")
    app = FastAPI()
    app.state.store = store
    app.include_router(route.router, prefix="/deadwax/library")
    route._cache_loaded_for = None

    response = TestClient(app).post("/deadwax/library/retag/apply",
                                    json={"album_path": here, "release": RELEASE})
    route._cache_loaded_for = None

    assert response.status_code == 200
    assert response.json()["results"].get("merged")
    reviews = asyncio.run(store.album_reviews())
    assert here not in reviews
    assert reviews[there]["ignored_issues"] == ["no_art"]
    assert reviews[there]["first_seen"] == first_seen
    assert reviews[there]["reviewed_at"]
