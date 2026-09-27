"""
Album folder names from a template (v0.9.17).

The default must be byte-for-byte the name deadwax has always written - every organizer, retag
and editions test runs under it unchanged. A custom template has to work both ways: the organizer
renders it, and the scan and the "folder off-convention" check read the edition back out of it.
"""

import pytest

from src.config import Config
from src.naming import DEFAULT_ALBUM_FOLDER, edition_from_folder, render_album_folder, validate_template
from src.organizer import build_album_dirname, build_target_path

WYWH = {"album": "Wish You Were Here", "original_year": "1975", "year": "2011-09-26", "album_artist": "Pink Floyd",
        "disambiguation": "2011 remaster", "media_format": "CD", "country": "GB", "catalog_number": "5099902895529"}
DUMMY = {"album": "Dummy", "original_year": "1994", "year": "1994", "album_artist": "Portishead"}


@pytest.fixture
def template(monkeypatch):
    def use(value):
        monkeypatch.setattr(Config, "ALBUM_FOLDER_TEMPLATE", value)
    return use


def test_the_default_is_the_long_standing_convention(template):
    template("")
    assert build_album_dirname(WYWH) == "Wish You Were Here (1975) [2011 remaster]"
    assert build_album_dirname(DUMMY) == "Dummy (1994)"
    assert build_album_dirname(DUMMY, "5b6c1a2d") == "Dummy (1994) [5b6c1a2d]"


def test_an_empty_token_takes_its_brackets_with_it():
    assert render_album_folder(DEFAULT_ALBUM_FOLDER, {"album": "Dummy", "year": "", "edition": ""}) == "Dummy"
    assert render_album_folder("{year} - {album}", {"album": "Dummy", "year": ""}) == "Dummy"


def test_a_custom_template_names_the_folder(template):
    template("{year} - {album} [{edition}] ({format})")
    assert build_album_dirname(WYWH) == "1975 - Wish You Were Here [2011 remaster] (CD)"
    assert build_album_dirname(DUMMY) == "1994 - Dummy"


def test_the_pressings_year_is_there_when_wanted(template):
    template("{album} ({release_year})")
    assert build_album_dirname(WYWH) == "Wish You Were Here (2011)"


def test_a_collision_is_still_resolved_without_an_edition_token(template):
    template("{year} - {album}")
    assert build_album_dirname(DUMMY, "alt") == "1994 - Dummy [alt]"


def test_the_artist_folder_is_always_the_artist(template, tmp_path):
    template("{year} - {album}")
    path = build_target_path(str(tmp_path), DUMMY, {"position": 1, "title": "Mysterons"}, "flac")
    assert path.relative_to(tmp_path).as_posix() == "Portishead/1994 - Dummy/01 - Mysterons.flac"


def test_an_unusable_template_never_names_a_folder(template):
    template("{bogus}")
    assert build_album_dirname(DUMMY) == "Dummy (1994)"


@pytest.mark.parametrize("value, problem", [
    ("{album} ({year})", None),
    ("", "a template can't be empty"),
    ("{artist}/{album}", "it names the album folder only"),
    ("{year}", "it needs {album}"),
    ("{album} {genre}", "unknown token: {genre}"),
    ("{album} {", "a { or } that isn't part of a token"),
])
def test_validation(value, problem):
    found = validate_template(value)
    assert (found is None) if problem is None else found.startswith(problem)


@pytest.mark.parametrize("template, name, edition", [
    (DEFAULT_ALBUM_FOLDER, "Dummy (1994) [20th Anniversary Reissue]", "20th Anniversary Reissue"),
    (DEFAULT_ALBUM_FOLDER, "Dummy (1994)", ""),
    (DEFAULT_ALBUM_FOLDER, "Album (Live) (1994) [Deluxe - 5b6c1a2d]", "Deluxe - 5b6c1a2d"),
    (DEFAULT_ALBUM_FOLDER, "Album (1994) [A] [B]", "B"),
    ("{year} - {album} [{edition}] ({format})", "1975 - Wish You Were Here [2011 remaster] (CD)", "2011 remaster"),
    ("{year} - {album} [{edition}] ({format})", "1994 - Dummy (CD)", ""),
    ("{year} - {album}", "1994 - Dummy", ""),
])
def test_the_edition_reads_back_out_of_the_name(template, name, edition):
    assert edition_from_folder(template, name) == edition


def test_under_a_custom_template_filed_albums_are_not_off_convention(template, tmp_path):
    """The scan reads the edition back and the check rebuilds the name - both through the template."""
    from src.library import clear_scan_cache, scan_library
    from src.metadata_health import inspect_album
    from tests.test_retag import write_flac

    template("{year} - {album} [{edition}]")
    folder = tmp_path / "Pink Floyd" / build_album_dirname(WYWH)
    write_flac(folder / "01 - Shine On.flac", album="Wish You Were Here", albumartist="Pink Floyd",
               artist="Pink Floyd", title="Shine On", tracknumber="1", date="2011", originaldate="1975")
    clear_scan_cache()
    [album] = scan_library(str(tmp_path))["albums"]

    assert folder.name == "1975 - Wish You Were Here [2011 remaster]"
    assert album["edition"] == "2011 remaster"
    assert "misfiled" not in inspect_album(album)


def test_the_setting_refuses_an_unusable_template():
    from src.routes.settings import _validate
    assert _validate("ALBUM_FOLDER_TEMPLATE", "{album} ({year})") is None
    assert _validate("ALBUM_FOLDER_TEMPLATE", "") is None  # empty means the default
    assert "needs {album}" in _validate("ALBUM_FOLDER_TEMPLATE", "{year}")
