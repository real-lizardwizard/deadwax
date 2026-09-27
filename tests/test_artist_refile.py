"""
One artist under two folder names, noticed and put right (v0.9.14).

An artist who renamed ends up split - `Kanye West/` for albums filed before deadwax filed under
current names, `Ye/` since - and the tree shows two artists. The scan notices (the same artist id
under two folder names); the artist page moves the old ones under the current name.
"""

import asyncio
from types import SimpleNamespace

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
