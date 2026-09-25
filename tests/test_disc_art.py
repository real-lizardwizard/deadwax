"""
CD art, and the pictures embedded in tracks.

Both came out of one question - why songs in Amperfy showed pictures that didn't match their
album. Navidrome shows a song's OWN embedded picture first, and otherwise its disc's artwork,
which it looks for as `disc*`/`cd*` images beside the tracks. So the track view now says what a
file carries, and deadwax can put a proper picture of the disc in that slot.
"""

import asyncio
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from mutagen.flac import FLAC, Picture

from src.config import Config
from src.disc_art import (choose_from_caa, choose_from_fanarttv, disc_art_filename, plan_disc_art,
                          save_disc_art)
from src.library import (describe_pictures, find_disc_art, read_album_dir, read_embedded_art,
                         read_track_details)
from tests.test_retag import seed, write_flac

ALBUM = "Tame Impala/The Slow Rush (2020)"
FIRST = "01 - One More Year.flac"
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 2048
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 2048


def run(coro):
    return asyncio.run(coro)


def embed(path, *pictures):
    """Add pictures to a FLAC: (type, mime, data, description)."""
    audio = FLAC(str(path))
    for kind, mime, data, desc in pictures:
        picture = Picture()
        picture.type, picture.mime, picture.data, picture.desc = kind, mime, data, desc
        audio.add_picture(picture)
    audio.save()


def paths(tmp_path):
    return sorted(p.name for p in tmp_path.rglob("*") if p.is_file())


# ------------------------------------------------------------------ embedded pictures


def test_every_embedded_picture_is_listed_in_file_order_without_its_bytes(tmp_path):
    directory = seed(tmp_path)
    embed(directory / FIRST, (6, "image/jpeg", JPEG, "cd scan"), (3, "image/png", PNG, ""))

    pictures = describe_pictures(directory / FIRST)

    assert [(p["index"], p["label"], p["mime"], p["description"]) for p in pictures] == [
        (0, "Media (the disc itself)", "image/jpeg", "cd scan"), (1, "Front cover", "image/png", "")]
    assert pictures[0]["size"] == len(JPEG)
    assert "data" not in pictures[0]


def test_the_album_cover_still_prefers_the_front_over_a_disc_scan(tmp_path):
    directory = seed(tmp_path)
    embed(directory / FIRST, (6, "image/jpeg", JPEG, ""), (3, "image/png", PNG, ""))
    assert read_embedded_art(directory / FIRST) == (PNG, "image/png")


def test_track_details_say_what_the_file_carries(tmp_path):
    directory = seed(tmp_path)
    embed(directory / FIRST, (3, "image/png", PNG, ""))

    assert [p["label"] for p in read_track_details(directory / FIRST)["pictures"]] == ["Front cover"]
    assert read_track_details(directory / "02 - Instant Destiny.flac")["pictures"] == []


# ------------------------------------------------------------------ disc images on disk


@pytest.mark.parametrize("name, counted", [
    ("disc.png", True), ("disc2.jpg", True), ("cd.jpg", True), ("CD 1.png", True), ("Disc_2.JPG", True),
    ("Discovery.jpg", False), ("cover.jpg", False), ("cd.txt", False), ("discography.png", False),
])
def test_disc_images_are_named_the_way_players_look_for_them(tmp_path, name, counted):
    (tmp_path / name).write_bytes(JPEG)
    assert find_disc_art(sorted(tmp_path.iterdir())) == ([name] if counted else [])


def test_the_scan_carries_the_disc_images(tmp_path):
    directory = seed(tmp_path)
    (directory / "cd.jpg").write_bytes(JPEG)
    (directory / "cover.jpg").write_bytes(JPEG)

    album = read_album_dir(directory, tmp_path)

    assert album["disc_art"] == ["cd.jpg"]
    assert album["art"] == "file"


# ------------------------------------------------------------------ choosing


def caa(types, comment="", n=1):
    return {"types": types, "comment": comment, "image": f"https://caa/{n}.jpg",
            "thumbnails": {"250": f"https://caa/{n}-250.jpg", "500": f"https://caa/{n}-500.jpg",
                           "1200": f"https://caa/{n}-1200.jpg", "small": f"https://caa/{n}-250.jpg",
                           "large": f"https://caa/{n}-500.jpg"}}


def test_only_a_picture_of_the_disc_is_taken_from_the_archive():
    assert choose_from_caa([caa(["Front"]), caa(["Back"])], []) == {}
    assert choose_from_caa([caa(["Front"], n=1), caa(["Medium"], n=2)], []) == {None: "https://caa/2-500.jpg"}


@pytest.mark.parametrize("size, url", [
    ("250", "https://caa/1-250.jpg"), ("500", "https://caa/1-500.jpg"),
    ("1200", "https://caa/1-1200.jpg"), ("full", "https://caa/1.jpg"),
])
def test_disc_art_is_saved_at_the_cover_art_size(size, url):
    assert choose_from_caa([caa(["Medium"])], [], size) == {None: url}


def test_a_set_is_numbered_by_what_each_image_says_it_is():
    images = [caa(["Medium"], "CD2", n=2), caa(["Medium"], "Disc 1", n=1)]
    assert choose_from_caa(images, [1, 2]) == {1: "https://caa/1-500.jpg", 2: "https://caa/2-500.jpg"}


def test_a_set_with_one_unnumbered_image_per_disc_takes_them_in_order():
    images = [caa(["Medium"], n=1), caa(["Medium"], n=2)]
    assert choose_from_caa(images, [1, 2]) == {1: "https://caa/1-500.jpg", 2: "https://caa/2-500.jpg"}


def test_otherwise_one_image_stands_for_every_disc_rather_than_a_guessed_order():
    images = [caa(["Medium"], n=1), caa(["Medium"], n=2), caa(["Medium"], n=3)]
    assert choose_from_caa(images, [1, 2]) == {None: "https://caa/1-500.jpg"}


def test_fanarttv_gives_the_most_liked_disc_art_per_disc():
    arts = [{"url": "a", "disc": "1", "likes": "2"}, {"url": "b", "disc": "1", "likes": "9"},
            {"url": "c", "disc": "2", "likes": "0"}]
    assert choose_from_fanarttv(arts, []) == {None: "b"}
    assert choose_from_fanarttv(arts, [1, 2]) == {1: "b", 2: "c"}
    assert choose_from_fanarttv(arts, [1, 2, 3]) == {1: "b", 2: "c"}
    assert choose_from_fanarttv([], [1]) == {}


def test_the_names_are_the_ones_navidrome_matches_to_a_disc():
    assert disc_art_filename(None, "image/png") == "disc.png"
    assert disc_art_filename(2, "image/jpeg") == "disc2.jpg"


# ------------------------------------------------------------------ planning and writing


def test_the_plan_reads_the_release_and_the_discs_from_the_tags(tmp_path):
    directory = seed(tmp_path, musicbrainz_albumid="rel-1", musicbrainz_releasegroupid="rg-1")
    write_flac(directory / "03 - Two.flac", title="Two", artist="Tame Impala",
               musicbrainz_albumid="rel-1", discnumber="2/2")
    (directory / "cd.jpg").write_bytes(JPEG)

    plan = plan_disc_art(ALBUM, str(tmp_path))

    assert (plan["release_mbid"], plan["release_group_mbid"], plan["discs"]) == ("rel-1", "rg-1", [2])
    #? a download's cd.jpg scan doesn't count as deadwax's own - a fetched disc.* wins over it
    assert plan["existing"] == []


@pytest.mark.parametrize("album_path", ["../..", "", "Tame Impala/../../outside"])
def test_nothing_outside_the_library_is_planned_or_written(tmp_path, album_path):
    library = tmp_path / "library"
    seed(library)
    assert plan_disc_art(album_path, str(library))["problem"]
    assert save_disc_art(album_path, str(library), [("disc.png", PNG)])["problems"]
    assert "disc.png" not in paths(tmp_path)


@pytest.mark.parametrize("name", ["cover.jpg", "../disc.png", "disc.png/../../x.png", "disc.exe", "artist.jpg"])
def test_only_names_it_makes_are_written(tmp_path, name):
    seed(tmp_path)
    before = paths(tmp_path)
    assert save_disc_art(ALBUM, str(tmp_path), [(name, PNG)])["problems"]
    assert paths(tmp_path) == before


def test_disc_art_already_there_is_never_replaced(tmp_path):
    directory = seed(tmp_path)
    (directory / "disc.png").write_bytes(b"mine")

    assert save_disc_art(ALBUM, str(tmp_path), [("disc.png", PNG)])["written"] == []
    assert (directory / "disc.png").read_bytes() == b"mine"


# ------------------------------------------------------------------ the routes


def request():
    return SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace()))


class Archive:
    def __init__(self, images):
        self.images, self.fetched = images, []

    async def release_images(self, mbid):
        return self.images

    async def fetch_image(self, url):
        self.fetched.append(url)
        return JPEG, "image/jpeg"


class Fanart:
    def __init__(self, cdart):
        self.cdart = cdart

    async def fanarttv_cdart(self, mbid):
        return self.cdart

    async def fetch(self, url):
        return PNG, "image/png"


@pytest.fixture
def routes(tmp_path, monkeypatch):
    from src.routes import library as routes
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "COVER_ART_SIZE", "500")
    monkeypatch.setattr(routes, "forget_cached_album", lambda path: None)
    return routes


def test_the_archives_disc_is_saved_for_the_release_the_album_is_tagged_with(tmp_path, routes, monkeypatch):
    directory = seed(tmp_path, musicbrainz_albumid="rel-1")
    archive = Archive([caa(["Front"], n=1), caa(["Medium"], n=2)])
    monkeypatch.setattr(routes, "coverart_client", archive)
    monkeypatch.setattr(routes, "artist_images_client", Fanart(None))

    answer = run(routes.fetch_disc_art(request(), routes.DiscArtRequest(album_path=ALBUM)))

    assert answer == {"written": ["disc.jpg"], "source": "the Cover Art Archive"}
    assert archive.fetched == ["https://caa/2-500.jpg"]
    assert (directory / "disc.jpg").read_bytes() == JPEG


def test_fanarttv_is_asked_when_the_archive_has_no_disc(tmp_path, routes, monkeypatch):
    directory = seed(tmp_path, musicbrainz_albumid="rel-1", musicbrainz_releasegroupid="rg-1")
    monkeypatch.setattr(routes, "coverart_client", Archive([caa(["Front"])]))
    monkeypatch.setattr(routes, "artist_images_client", Fanart([{"url": "u", "disc": "1", "likes": "1"}]))

    answer = run(routes.fetch_disc_art(request(), routes.DiscArtRequest(album_path=ALBUM)))

    assert answer["source"] == "fanart.tv"
    assert (directory / "disc.png").read_bytes() == PNG


@pytest.mark.parametrize("images, status", [([], 404), (None, 502)])
def test_no_disc_anywhere_and_the_archive_being_down_are_told_apart(tmp_path, routes, monkeypatch, images, status):
    seed(tmp_path, musicbrainz_albumid="rel-1")
    monkeypatch.setattr(routes, "coverart_client", Archive(images))
    monkeypatch.setattr(routes, "artist_images_client", Fanart(None))

    with pytest.raises(HTTPException) as refused:
        run(routes.fetch_disc_art(request(), routes.DiscArtRequest(album_path=ALBUM)))

    assert refused.value.status_code == status


def test_an_untagged_album_is_told_to_match_a_release_first(tmp_path, routes, monkeypatch):
    seed(tmp_path)
    monkeypatch.setattr(routes, "coverart_client", Archive([caa(["Medium"])]))

    with pytest.raises(HTTPException) as refused:
        run(routes.fetch_disc_art(request(), routes.DiscArtRequest(album_path=ALBUM)))

    assert "match it to one first" in refused.value.detail


def test_an_album_with_disc_art_already_is_refused(tmp_path, routes, monkeypatch):
    directory = seed(tmp_path, musicbrainz_albumid="rel-1")
    (directory / "disc.png").write_bytes(b"mine")
    monkeypatch.setattr(routes, "coverart_client", Archive([caa(["Medium"])]))

    with pytest.raises(HTTPException) as refused:
        run(routes.fetch_disc_art(request(), routes.DiscArtRequest(album_path=ALBUM)))

    assert refused.value.status_code == 400
    assert (directory / "disc.png").read_bytes() == b"mine"


def test_a_tracks_picture_is_served_by_index(tmp_path, routes):
    directory = seed(tmp_path)
    embed(directory / FIRST, (6, "image/jpeg", JPEG, ""), (3, "image/png", PNG, ""))

    response = run(routes.track_picture(ALBUM, FIRST, 1))

    assert (response.body, response.media_type) == (PNG, "image/png")


@pytest.mark.parametrize("album, file, index", [
    ("../..", FIRST, 0), (ALBUM, "../../../etc/passwd", 0), (ALBUM, "cover.jpg", 0), (ALBUM, FIRST, 5),
])
def test_anything_but_a_picture_in_a_track_is_404(tmp_path, routes, album, file, index):
    directory = seed(tmp_path)
    (directory / "cover.jpg").write_bytes(JPEG)
    embed(directory / FIRST, (3, "image/png", PNG, ""))

    with pytest.raises(HTTPException) as refused:
        run(routes.track_picture(album, file, index))

    assert refused.value.status_code == 404


def test_only_disc_images_are_served_as_disc_art(tmp_path, routes):
    directory = seed(tmp_path)
    (directory / "disc.png").write_bytes(PNG)
    (directory / "cover.jpg").write_bytes(JPEG)

    assert run(routes.disc_art(ALBUM, "disc.png")).body == PNG
    for name in ("cover.jpg", "../disc.png", FIRST):
        with pytest.raises(HTTPException):
            run(routes.disc_art(ALBUM, name))
