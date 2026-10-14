"""
One artist under two folder names, noticed and put right (v0.9.14).

An artist who renamed ends up split - `Kanye West/` for albums filed before deadwax filed under
current names, `Ye/` since - and the tree shows two artists. The scan notices (the same artist id
under two folder names); the artist page moves the old ones under the current name.
"""

import asyncio
import os
from types import SimpleNamespace

import pytest

from mutagen.flac import FLAC

from src.artist_refile import execute_artist_refile, plan_artist_refile
from src.library import clear_scan_cache, scan_library
from src.metadata_health import inspect_album
from tests.test_retag import write_flac

YE = "ye-mbid"


def album(root, folder, name, albumartist, ids=(YE,), titles=("One", "Two")):
    directory = root / folder / name
    for n, title in enumerate(titles, start=1):
        path = write_flac(directory / f"{n:02d} {title}.flac", album=name, albumartist=albumartist,
                          artist=albumartist, title=title, tracknumber=str(n), date="2021")
        if ids:
            audio = FLAC(str(path))
            audio["musicbrainz_albumartistid"] = list(ids)
            audio.save()
    return directory


def scan(root):
    clear_scan_cache()
    return scan_library(str(root))["albums"]


def test_one_artist_id_under_two_folder_names_is_noticed(tmp_path):
    album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    album(tmp_path, "Ye", "BULLY (2025)", "Ye")
    album(tmp_path, "Portishead", "Dummy (1994)", "Portishead", ids=("portishead",))

    by_path = {a["path"]: a for a in scan(tmp_path)}

    assert by_path["Kanye West/Donda (2021)"]["artist_folders"] == ["Kanye West", "Ye"]
    assert "artist_split" in inspect_album(by_path["Ye/BULLY (2025)"])
    assert by_path["Portishead/Dummy (1994)"]["artist_folders"] == []


def test_a_collaboration_is_never_counted(tmp_path):
    album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    album(tmp_path, "JAY-Z & Ye", "Watch the Throne (2011)", "JAY-Z & Ye", ids=("jay-z", YE))
    assert all(a["artist_folders"] == [] for a in scan(tmp_path))


def plan_for(root, name="Kanye West"):
    albums = [a for a in scan(root) if a["artist"] == name]
    return plan_artist_refile(str(root), albums, "Ye", YE)


def test_the_plan_moves_the_album_artist_and_never_the_credit(tmp_path):
    album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")

    plan = plan_for(tmp_path)

    assert plan["to_folder"] == "Ye"
    [move] = plan["moves"]
    assert move["target_path"] == "Ye/Donda (2021)"
    assert {change for entry in move["retag"] for change in entry["changes"]} == {"albumartist"}


def test_an_album_already_filed_under_the_new_name_is_refused_not_overwritten(tmp_path):
    album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    album(tmp_path, "Ye", "Donda (2021)", "Ye")

    plan = plan_for(tmp_path)

    assert plan["moves"] == []
    assert plan["refused"][0]["reason"] == "'Ye/Donda (2021)' is already there"


def test_an_album_tagged_as_someone_else_stays(tmp_path):
    album(tmp_path, "Kanye West", "Tribute (2022)", "Kanye West", ids=("tribute-band",))
    assert plan_for(tmp_path)["refused"][0]["reason"] == "tagged as a different artist"


def test_untagged_ids_are_written_as_well(tmp_path):
    album(tmp_path, "Kanye West", "808s (2008)", "Kanye West", ids=())
    [move] = plan_for(tmp_path)["moves"]
    assert move["retag"][0]["changes"]["musicbrainz_albumartistid"] == {"from": "", "to": YE}


def test_executing_moves_retags_carries_the_pictures_and_removes_the_old_folder(tmp_path):
    album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    album(tmp_path, "Kanye West", "Jesus Is King (2019)", "Kanye West")
    (tmp_path / "Kanye West" / "artist.jpg").write_bytes(b"portrait")
    (tmp_path / "Kanye West" / "notes.txt").write_text("mine")

    results = execute_artist_refile(plan_for(tmp_path), str(tmp_path))

    assert sorted(m["to"] for m in results["moved"]) == ["Ye/Donda (2021)", "Ye/Jesus Is King (2019)"]
    assert results["pictures_moved"] == ["artist.jpg"]
    assert (tmp_path / "Ye" / "artist.jpg").read_bytes() == b"portrait"
    #? a file that isn't an artist picture keeps the old folder - rmdir, never rmtree
    assert (tmp_path / "Kanye West" / "notes.txt").exists()
    assert results["removed_folders"] == []
    tags = FLAC(str(tmp_path / "Ye" / "Donda (2021)" / "01 One.flac"))
    assert tags["albumartist"] == ["Ye"] and tags["artist"] == ["Kanye West"]


def test_an_appledouble_twin_is_never_retagged_and_moves_with_its_folder(tmp_path):
    #? 2.0.0-player.45, found moving the stub library in the app's real page: a Mac copying to a share
    #? leaves `._<name>` beside every file - its resource fork, named .flac, which no tag can be
    #? written to. Planned as a retag, it failed the whole album ("a tag wouldn't write").
    directory = album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    (directory / "._01 One.flac").write_bytes(b"\x00\x05\x16\x07" + b"\x00" * 60)
    (directory / "._02 Two.flac").write_bytes(b"\x00\x05\x16\x07" + b"\x00" * 60)

    [move] = plan_for(tmp_path)["moves"]
    assert (move["files"], sorted(entry["filename"] for entry in move["retag"])) == (2, ["01 One.flac", "02 Two.flac"])

    results = execute_artist_refile(plan_for(tmp_path), str(tmp_path))
    assert (results["moved"], results["failed"]) == ([{"from": "Kanye West/Donda (2021)", "to": "Ye/Donda (2021)"}], [])
    assert (tmp_path / "Ye" / "Donda (2021)" / "._01 One.flac").read_bytes().startswith(b"\x00\x05\x16\x07")
    assert FLAC(str(tmp_path / "Ye" / "Donda (2021)" / "01 One.flac"))["albumartist"] == ["Ye"]


def _stays_untouched(tmp_path, reason):
    """The plan refuses Donda, saying why, and executing it writes and moves nothing."""
    plan = plan_for(tmp_path)
    assert plan["moves"] == [] and plan["refused"] == [{"album": "Donda (2021)", "path": "Kanye West/Donda (2021)", "reason": reason}]
    results = execute_artist_refile(plan, str(tmp_path))
    assert (results["moved"], results["failed"]) == ([], [])
    assert not (tmp_path / "Ye").exists()
    assert FLAC(str(tmp_path / "Kanye West" / "Donda (2021)" / "01 One.flac"))["albumartist"] == ["Kanye West"]


def test_a_track_cut_short_keeps_its_album_where_it_is_and_the_preview_says_why(tmp_path):
    #? review (2.0.0-player.45): only the `._` twins are passed over. A real track that won't open -
    #? here cut off 60 bytes in - can't have its tag rewritten, and moved it would still name the old
    #? artist under the new one; refused in the plan, so nothing is half written either
    directory = album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West", titles=("One", "Two", "Three"))
    track = directory / "03 Three.flac"
    track.write_bytes(track.read_bytes()[:60])
    _stays_untouched(tmp_path, "'03 Three.flac' can't be read, so its tags can't be written")


def test_an_mp3_whose_tag_reads_but_whose_audio_does_not_keeps_its_album_where_it_is(tmp_path):
    #? a good ID3 tag naming the old artist over nothing mutagen can sync to: a more forgiving reader
    #? (Navidrome's taglib) would still list it as Kanye West's
    from mutagen.id3 import ID3, TALB, TPE2
    directory = album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    broken = directory / "03 Three.mp3"
    broken.write_bytes(b"\x00" * 20000)
    tag = ID3()
    tag.add(TPE2(encoding=3, text="Kanye West"))
    tag.add(TALB(encoding=3, text="Donda"))
    tag.save(str(broken))
    _stays_untouched(tmp_path, "'03 Three.mp3' can't be read, so its tags can't be written")
    assert ID3(str(broken))["TPE2"].text == ["Kanye West"]


@pytest.mark.parametrize("extension", ["m4a", "ogg", "opus"])
def test_a_track_mutagen_cannot_even_recognise_keeps_its_album_where_it_is(tmp_path, extension):
    #? review (2.0.0-player.45): an .m4a, .ogg or .opus mutagen doesn't recognise - an incomplete
    #? download, pre-allocated and never filled - isn't an error it raises but None it answers (MP4 and
    #? Ogg are known by their header, not their name). Taken for a file with no tags, it was planned as a
    #? retag, and executing the move rewrote the good tracks before failing on it: half written
    from src.tagkeys import easy_file
    directory = album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    hollow = directory / f"03 Three.{extension}"
    hollow.write_bytes(b"\x00" * 200)
    assert easy_file(hollow) is None
    _stays_untouched(tmp_path, f"'03 Three.{extension}' can't be read, so its tags can't be written")
    assert FLAC(str(directory / "02 Two.flac"))["albumartist"] == ["Kanye West"]


def test_several_tracks_that_wont_open_are_counted_in_the_one_reason(tmp_path):
    directory = album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West", titles=("One", "Two", "Three", "Four"))
    for name in ("03 Three.flac", "04 Four.flac"):
        (directory / name).write_bytes(b"fLaC" + b"\x00" * 10)
    _stays_untouched(tmp_path, "2 of its files can't be read ('03 Three.flac' and 1 more), so their tags can't be written")


@pytest.mark.skipif(os.name != "posix" or os.geteuid() == 0, reason="root reads a file whatever its mode")
def test_a_track_deadwaxs_user_cannot_read_keeps_its_album_where_it_is(tmp_path):
    #? a share where files have different owners: Navidrome, reading as another user, still sees it
    directory = album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    locked = directory / "02 Two.flac"
    locked.chmod(0)
    try:
        _stays_untouched(tmp_path, "'02 Two.flac' can't be read, so its tags can't be written")
    finally:
        locked.chmod(0o644)


def test_the_old_folder_goes_once_nothing_is_left_in_it(tmp_path):
    album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    results = execute_artist_refile(plan_for(tmp_path), str(tmp_path))
    assert results["removed_folders"] == ["Kanye West"]
    assert not (tmp_path / "Kanye West").exists()


def test_pictures_stay_while_an_album_is_left_behind(tmp_path):
    album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    album(tmp_path, "Kanye West", "Tribute (2022)", "Kanye West", ids=("tribute-band",))
    (tmp_path / "Kanye West" / "artist.jpg").write_bytes(b"portrait")

    results = execute_artist_refile(plan_for(tmp_path), str(tmp_path))

    assert results["pictures_moved"] == []
    assert (tmp_path / "Kanye West" / "artist.jpg").exists()


def test_the_route_asks_musicbrainz_for_the_current_name(tmp_path, monkeypatch):
    from src.config import Config
    from src.routes import library as routes

    album(tmp_path, "Kanye West", "Donda (2021)", "Kanye West")
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    clear_scan_cache()

    class MusicBrainz:
        async def get_artist(self, mbid):
            return {"id": mbid, "name": "Ye", "aliases": []}

    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(musicbrainz_client=MusicBrainz(), store=None)))
    body = routes.ArtistRefileRequest(artist="Kanye West")

    preview = asyncio.run(routes.artist_refile_preview(request, body))
    assert (preview["current_name"], [m["target_path"] for m in preview["moves"]]) == ("Ye", ["Ye/Donda (2021)"])

    applied = asyncio.run(routes.artist_refile_apply(request, body))
    assert applied["results"]["moved"] == [{"from": "Kanye West/Donda (2021)", "to": "Ye/Donda (2021)"}]
    assert (tmp_path / "Ye" / "Donda (2021)").is_dir()
