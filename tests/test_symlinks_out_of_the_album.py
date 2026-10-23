"""
Pictures and .lrc files that are symlinks out of their folder (2.0.0-player.65, the 2.0.0 release review).

A folder listing's `is_file()` follows a symlink, so a `cover.jpg` that is a link to a file elsewhere passes on its
name. Planting one needs write access to the library, but then:

  - READ, the cover and artist picture routes served whatever it pointed at - /disc_art had refused that since
    1.0.x, by checking the file itself resolves inside its folder; covers and artist pictures now do the same
    (a cover refused is passed over for the embedded art);
  - WRITTEN, saving a cover, an artist picture, CD art or a .lrc wrote through the link, wherever it pointed -
    outside the library too. Every writer now refuses a name that is a symlink, a dangling one included, and
    says so; nothing outside is touched.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.config import Config  # noqa: E402
from src.library import load_album_art, load_artist_art  # noqa: E402
from src.organizer import LINK_REFUSED  # noqa: E402

JPEG = b"\xff\xd8\xff\xe0" + b"deadwax" * 8
SECRET = b"not a picture: a file outside the library"


@pytest.fixture
def layout(tmp_path):
    """A library with one album, and a file outside it the links point at."""
    library = tmp_path / "library"
    album = library / "Artist" / "Album (1994)"
    album.mkdir(parents=True)
    outside = tmp_path / "outside" / "secret.jpg"
    outside.parent.mkdir()
    outside.write_bytes(SECRET)
    return library, album, outside


# ----------------------------------------------------------------- reads

def test_a_cover_that_links_out_of_the_album_is_not_served(layout):
    library, album, outside = layout
    (album / "cover.jpg").symlink_to(outside)
    assert load_album_art(album) is None


def test_a_real_cover_is_still_served(layout):
    library, album, outside = layout
    (album / "cover.jpg").write_bytes(JPEG)
    assert load_album_art(album) == (JPEG, "image/jpeg")


def test_a_cover_linked_inside_the_album_is_still_served(layout):
    """A link to a file in the same folder is no way out of it."""
    library, album, outside = layout
    (album / "front-scan.jpg").write_bytes(JPEG)
    (album / "cover.jpg").symlink_to(album / "front-scan.jpg")
    assert load_album_art(album) == (JPEG, "image/jpeg")


def test_an_artist_picture_that_links_out_of_the_folder_is_not_served(layout):
    library, album, outside = layout
    (album.parent / "artist.jpg").symlink_to(outside)
    assert load_artist_art(album.parent, "thumb") is None
    (album.parent / "artist.jpg").unlink()
    (album.parent / "artist.jpg").write_bytes(JPEG)
    assert load_artist_art(album.parent, "thumb") == (JPEG, "image/jpeg")


# ----------------------------------------------------------------- writes

@pytest.mark.parametrize("dangling", [False, True])
def test_saving_a_cover_never_writes_through_a_link(layout, dangling):
    from src.retag import save_cover_art

    library, album, outside = layout
    target = outside.parent / "made-by-the-link.jpg" if dangling else outside
    (album / "cover.jpg").symlink_to(target)

    result = save_cover_art("Artist/Album (1994)", str(library), (JPEG, "image/jpeg"))

    assert result == {"written": None, "problem": f"cover.jpg {LINK_REFUSED}"}
    assert outside.read_bytes() == SECRET and not (outside.parent / "made-by-the-link.jpg").exists()


def test_saving_an_artist_picture_never_writes_through_a_link(layout, monkeypatch):
    from src.artist_art import execute_artist_art, plan_artist_art

    library, album, outside = layout
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(library))
    (album.parent / "artist.jpg").symlink_to(outside)

    plan = plan_artist_art("Artist", ["thumb"], str(library), replace=True)
    result = execute_artist_art(plan, {"thumb": (JPEG, "image/jpeg")}, mode="apply")

    assert result["written"] == [] and result["problems"] == [f"artist.jpg {LINK_REFUSED}"]
    assert outside.read_bytes() == SECRET


@pytest.mark.parametrize("dangling", [False, True])
def test_saving_cd_art_never_writes_through_a_link(layout, dangling):
    from src.disc_art import save_disc_art

    library, album, outside = layout
    target = outside.parent / "made-by-the-link.jpg" if dangling else outside
    (album / "disc.jpg").symlink_to(target)

    result = save_disc_art("Artist/Album (1994)", str(library), [("disc.jpg", JPEG)], replace=True)

    assert result == {"written": [], "problems": [f"disc.jpg {LINK_REFUSED}"]}
    assert outside.read_bytes() == SECRET and not (outside.parent / "made-by-the-link.jpg").exists()


def test_saving_lyrics_never_writes_through_a_link(layout):
    from src.lyrics import execute_lyrics

    library, album, outside = layout
    (album / "01 Song.flac").write_bytes(b"fLaC")
    (album / "01 Song.lrc").symlink_to(outside)

    result = execute_lyrics("Artist/Album (1994)", str(library), {"01 Song.flac": "[00:01.00] la"}, replace=True)

    assert result == {"written": [], "problems": [f"01 Song.lrc {LINK_REFUSED}"]}
    assert outside.read_bytes() == SECRET
