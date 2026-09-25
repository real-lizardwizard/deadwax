"""
Artists: what a page shows, where their pictures come from, and writing those into the library.

The fifth writer gets the same treatment as the other four - most of this is what it REFUSES.
Two refusals matter more than the rest and neither is obvious:

  - a folder holding TRACKS is an album, not an artist. Writing `artist.*` and `folder.*` in
    there lands them where Navidrome reads album covers and album-level artist images.
  - applying only honours a URL the artist's own sources just offered. Without that, the apply
    route would fetch any address it was handed, from inside the network this container sits
    in, and write the answer into the library.
"""

from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from src.artist_art import artist_folder, execute_artist_art, plan_artist_art
from src.artists import (ARTIST_ART_KINDS, ARTIST_ART_STEMS, answers_to, artist_facts,
                         artist_names, artist_query, best_per_kind, commons_file_url,
                         commons_title, from_relations, from_theaudiodb, from_fanarttv,
                         from_wikidata, safe_thumb_width, wikidata_id)
from src.config import Config
from tests.test_retag import write_flac

ARTIST = "Dance Gavin Dance"


def seed_artist(root: Path) -> Path:
    """An artist folder with one album under it, as the organizer would have filed it."""
    album = root / ARTIST / "Jackpot Juicer (2022)"
    write_flac(album / "01 - Untitled 2.flac", title="Untitled 2", album="Jackpot Juicer",
               albumartist=ARTIST, artist=ARTIST, date="2022")
    return root / ARTIST


# ---------------------------------------------------------------- where pictures come from

def test_a_commons_file_page_becomes_a_picture():
    assert commons_title("https://commons.wikimedia.org/wiki/File:Portishead13b.jpg") == "Portishead13b.jpg"
    assert commons_title("https://commons.wikimedia.org/wiki/Special:FilePath/X.jpg") == "X.jpg"


def test_anything_that_is_not_commons_is_left_alone():
    #? an image relation can point anywhere - a band's own site, a dead image host - and only
    #? Commons can be turned into a file by guessing a URL
    assert commons_title("https://dancegavindanceband.com/photo.jpg") is None
    assert commons_title("https://en.wikipedia.org/wiki/File:X.jpg") is None
    assert commons_title("") is None


def test_a_commons_url_asks_for_a_thumbnail_when_it_is_going_to_be_looked_at():
    assert commons_file_url("Dance Gavin Dance.jpg").endswith("Dance_Gavin_Dance.jpg")
    assert commons_file_url("X.jpg", 600).endswith("?width=600")


def test_the_wikidata_id_comes_off_the_relation():
    rels = [{"type": "wikidata", "url": {"resource": "https://www.wikidata.org/wiki/Q3013333"}}]
    assert wikidata_id(rels) == "Q3013333"
    assert wikidata_id([{"type": "discogs", "url": {"resource": "https://discogs.com/artist/1"}}]) is None
    assert wikidata_id(None) is None


def test_musicbrainz_image_relations_become_thumb_candidates():
    rels = [
        {"type": "image", "url": {"resource": "https://commons.wikimedia.org/wiki/File:A.jpg"}},
        {"type": "image", "url": {"resource": "https://example.com/not-commons.jpg"}},
        {"type": "discogs", "url": {"resource": "https://discogs.com/artist/1"}},
    ]
    found = from_relations(rels)
    assert [c["kind"] for c in found] == ["thumb"]
    assert found[0]["source"] == "musicbrainz"


def test_wikidata_gives_an_image_and_a_logo():
    entity = {"claims": {
        "P18": [{"mainsnak": {"datavalue": {"value": "Band.jpg"}}}],
        "P154": [{"mainsnak": {"datavalue": {"value": "Band logo.svg"}}}],
    }}
    found = from_wikidata(entity)
    assert {c["kind"] for c in found} == {"thumb", "logo"}


def test_a_wikidata_claim_with_nothing_in_it_is_skipped_rather_than_crashed_on():
    #? claims are edited by hand and can be deprecated, novalue, or a number where a file name
    #? was expected - none of which should take an artist page down
    entity = {"claims": {"P18": [
        {"mainsnak": {}},
        {"mainsnak": {"datavalue": {"value": ""}}},
        {"mainsnak": {"datavalue": {"value": {"id": "Q1"}}}},
    ]}}
    assert from_wikidata(entity) == []
    assert from_wikidata(None) == []


def test_theaudiodb_is_the_only_source_with_the_shapes_a_page_needs():
    row = {
        "strArtistThumb": "https://x/thumb.jpg",
        "strArtistBanner": "https://x/banner.jpg",
        "strArtistLogo": "https://x/logo.png",
        "strArtistFanart": "https://x/fan1.jpg",
        "strArtistFanart2": "https://x/fan2.jpg",
        "strArtistWideThumb": "https://x/wide.jpg",
        "strArtistClearart": "",
    }
    kinds = {c["kind"] for c in from_theaudiodb(row)}
    assert {"thumb", "banner", "logo", "fanart", "landscape"} <= kinds
    assert "clearart" not in kinds, "an empty field is not a picture"


FANARTTV = {
    "artistthumb": [
        {"url": "https://f/thumb-unloved.jpg", "likes": "1"},
        {"url": "https://f/thumb-loved.jpg", "likes": "14"},
    ],
    "musicbanner": [{"url": "https://f/banner.jpg", "likes": "3"}],
    "artistbackground": [{"url": "https://f/bg.jpg", "likes": "9"}],
    "artist4kbackground": [{"url": "https://f/bg4k.jpg"}],
    "hdmusiclogo": [{"url": "https://f/hd.png", "likes": "20"}],
    "musiclogo": [{"url": "https://f/plain.png", "likes": "2"}],
}


def test_fanarttv_offers_every_kind_an_artist_page_is_made_of():
    kinds = {c["kind"] for c in from_fanarttv(FANARTTV)}
    assert {"thumb", "banner", "fanart", "logo"} == kinds


def test_the_most_liked_comes_first():
    """fanart.tv's pictures were put there by the people using them, so the votes mean something."""
    thumbs = [c for c in from_fanarttv(FANARTTV) if c["kind"] == "thumb"]
    assert thumbs[0]["url"] == "https://f/thumb-loved.jpg"


def test_the_hd_logo_is_offered_before_the_plain_one():
    logos = [c for c in from_fanarttv(FANARTTV) if c["kind"] == "logo"]
    assert logos[0]["url"] == "https://f/hd.png"


def test_a_4k_background_is_another_background_not_another_kind():
    #? offered alongside the ordinary ones, being several megabytes each
    backgrounds = [c for c in from_fanarttv(FANARTTV) if c["kind"] == "fanart"]
    assert {b["url"] for b in backgrounds} == {"https://f/bg.jpg", "https://f/bg4k.jpg"}


def test_only_so_many_of_one_kind():
    many = {"artistbackground": [{"url": f"https://f/{n}.jpg", "likes": str(n)} for n in range(12)]}
    assert len(from_fanarttv(many)) == 4, "a picker listing twelve backgrounds is one nobody reads"


def test_a_fanarttv_payload_that_is_junk_is_survived():
    assert from_fanarttv(None) == []
    assert from_fanarttv({}) == []
    assert from_fanarttv({"artistthumb": "not a list"}) == []
    assert from_fanarttv({"artistthumb": [{"likes": "5"}]}) == [], "no url is not a picture"


def test_likes_that_are_not_numbers_do_not_take_the_page_down():
    #? fanart.tv reports likes as a string, and has been known to leave it out
    odd = {"artistthumb": [{"url": "https://f/a.jpg", "likes": "lots"}, {"url": "https://f/b.jpg"}]}
    assert len(from_fanarttv(odd)) == 2


def test_fanarttv_is_asked_for_nothing_without_a_key(monkeypatch):
    import asyncio

    from src.api.artist_images_endpoint import ArtistImagesClient

    monkeypatch.setattr(Config, "FANARTTV_KEY", None)
    client = ArtistImagesClient()

    async def must_not_ask(*args, **kwargs):
        raise AssertionError("asked fanart.tv for something with no key configured")

    monkeypatch.setattr(client, "_json", must_not_ask)
    assert asyncio.run(client.fanarttv("some-mbid")) is None


def test_fanarttv_leads_when_two_sources_offer_the_same_kind():
    candidates = (from_theaudiodb({"strArtistThumb": "https://a/thumb.jpg"})
                  + from_fanarttv({"artistthumb": [{"url": "https://f/thumb.jpg", "likes": "4"}]}))
    assert best_per_kind(candidates)["thumb"]["source"] == "fanarttv"


def test_purpose_made_artwork_beats_a_photograph_of_a_stage():
    candidates = (from_wikidata({"claims": {"P18": [{"mainsnak": {"datavalue": {"value": "Live.jpg"}}}]}})
                  + from_theaudiodb({"strArtistThumb": "https://x/thumb.jpg"}))
    assert best_per_kind(candidates)["thumb"]["source"] == "theaudiodb"


def test_the_first_background_wins_over_its_alternates():
    best = best_per_kind(from_theaudiodb({
        "strArtistFanart": "https://x/one.jpg", "strArtistFanart2": "https://x/two.jpg",
    }))
    assert best["fanart"]["url"] == "https://x/one.jpg"


def test_commons_is_asked_for_a_thumbnail_under_the_originals_width():
    """
    Wikimedia serves thumbnails to robots and refuses originals - "Please honor our robot
    policy" - and MediaWiki will not upscale, so asking for more than the file has resolves to
    the original and is refused. Measured on a 367px file: 300 served, 366 did not.
    """
    assert safe_thumb_width(367, 600) == 330
    assert safe_thumb_width(4000, 1200) == 1200, "a big file is capped by what we want, not by itself"


def test_a_vector_is_not_shrunk():
    #? an SVG is rasterised at whatever width is asked for and comes back a PNG, so a logo
    #? keeps its size instead of being cut to the nominal one Commons reports
    assert safe_thumb_width(288, 1200, vector=True) == 1200


def test_an_unknown_width_leaves_the_asking_alone():
    assert safe_thumb_width(0, 600) == 600


def test_a_tiny_file_still_gets_a_usable_thumbnail():
    assert safe_thumb_width(40, 600) == 64


def test_commons_candidates_are_rewritten_to_thumbnails(monkeypatch):
    """End to end over the rule: what the picker shows and what gets written are both thumbs."""
    import asyncio

    from src.api.artist_images_endpoint import ArtistImagesClient

    client = ArtistImagesClient()

    async def fake_width(title):
        return 367

    monkeypatch.setattr(client, "commons_width", fake_width)

    candidates = [
        {"kind": "thumb", "url": "https://commons.wikimedia.org/wiki/Special:FilePath/A.jpg",
         "preview": "x", "source": "wikidata", "label": "Wikidata image"},
        {"kind": "banner", "url": "https://r2.theaudiodb.com/banner.jpg",
         "preview": "https://r2.theaudiodb.com/banner.jpg", "source": "theaudiodb", "label": "Banner"},
    ]

    resolved = asyncio.run(client._size_commons(candidates))

    assert resolved[0]["url"].endswith("?width=330")
    assert resolved[0]["preview"].endswith("?width=330")
    #? and a source that isn't Commons is left exactly as it was
    assert resolved[1] == candidates[1]


# ---------------------------------------------------------------- what a page shows

def test_an_artist_is_shaped_into_a_pages_terms():
    facts = artist_facts({
        "id": "abc", "name": "Dance Gavin Dance", "sort-name": "Dance Gavin Dance",
        "type": "Group", "country": "US", "area": {"name": "United States"},
        "life-span": {"begin": "2005", "ended": False},
        "genres": [{"name": "pop", "count": 2}, {"name": "post-hardcore", "count": 9}],
    })
    assert facts["name"] == "Dance Gavin Dance" and facts["began"] == "2005"
    #? by how many people said so, not alphabetically: the first few are the answer to "what is
    #? this band" and the tail is noise
    assert facts["genres"][0] == "post-hardcore"


def test_an_artist_with_almost_nothing_on_it_still_shapes():
    facts = artist_facts({"name": "Someone New"})
    assert facts["name"] == "Someone New"
    assert facts["genres"] == [] and facts["members"] == [] and facts["links"] == []
    assert artist_facts(None)["name"] == ""


def test_only_the_bands_own_members_are_listed():
    #? the relation hangs off both sides; forward would be the bands this artist is a member OF
    facts = artist_facts({"name": "A band", "relations": [
        {"type": "member of band", "direction": "backward", "begin": "2005",
         "artist": {"id": "1", "name": "Will Swan"}, "attributes": ["guitar"]},
        {"type": "member of band", "direction": "backward", "begin": "2007", "ended": True,
         "end": "2012", "artist": {"id": "2", "name": "Someone Else"}},
        {"type": "member of band", "direction": "forward", "artist": {"id": "3", "name": "Another Band"}},
    ]})
    assert [m["name"] for m in facts["members"]] == ["Will Swan", "Someone Else"]
    #? the current line-up first, which is what a page leads with
    assert facts["members"][0]["current"] and not facts["members"][1]["current"]


def test_links_are_grouped_and_never_repeated():
    facts = artist_facts({"name": "A band", "relations": [
        {"type": "official homepage", "url": {"resource": "https://band.com/"}},
        {"type": "social network", "url": {"resource": "https://twitter.com/band"}},
        {"type": "streaming", "url": {"resource": "https://tidal.com/artist/1"}},
        {"type": "social network", "url": {"resource": "https://twitter.com/band"}},
    ]})
    urls = [l["url"] for l in facts["links"]]
    assert urls.count("https://twitter.com/band") == 1
    assert facts["links"][0]["label"] == "Official site", "the official site leads"


def test_social_links_are_named_after_where_they_go():
    """MusicBrainz calls all of them "social network", so three of them read "Social, Social, Social"."""
    facts = artist_facts({"name": "A band", "relations": [
        {"type": "social network", "url": {"resource": "https://twitter.com/band"}},
        {"type": "social network", "url": {"resource": "https://www.facebook.com/band"}},
        {"type": "social network", "url": {"resource": "https://www.instagram.com/band/"}},
    ]})
    assert [l["label"] for l in facts["links"]] == ["Twitter", "Facebook", "Instagram"]



# ------------------------------------------------------- finding an artist who has been renamed
#
# MusicBrainz keeps one current name per artist and everything else as an alias, while each
# release keeps the name it was CREDITED under. deadwax writes the credit into the tags and the
# folder - correctly, the album really was credited that way - so the name on disk is the one
# MusicBrainz has stopped answering to. Measured against the live API before this was written:
# artist:"Kanye West" returned "Kanye West Tribute Band" and "Kanye West & Hatsune Miku", with
# Ye nowhere in the answer.

#? Ye's artist search result, trimmed to the fields that matter. Real: fetched from the live API.
YE = {
    "id": "164f0d73-1234-4e2c-8743-d77bf2191051", "name": "Ye", "sort-name": "Ye", "score": 100,
    "disambiguation": "formerly Kanye West",
    "aliases": [
        {"name": "Ye", "type": "Artist name", "primary": True},
        {"name": "KanYeWest", "type": "Search hint"},
        {"name": "Kanye", "type": "Artist name"},
        {"name": "Kayne West", "type": "Search hint"},
        {"name": "Kanye West", "type": "Artist name", "primary": True},
        {"name": "Kanye Omari West", "type": "Legal name"},
    ],
}


def test_the_query_asks_about_aliases_as_well_as_current_names():
    #? artist: alone cannot find anybody who has renamed, which is the entire bug
    query = artist_query("Kanye West")
    assert 'artist:"Kanye West"' in query and 'alias:"Kanye West"' in query


def test_the_query_is_bracketed_so_anything_ANDed_on_cannot_split_the_OR():
    assert artist_query("Ye").startswith("(") and artist_query("Ye").endswith(")")


@pytest.mark.parametrize("name", ['A "Live" Band', "AC\\DC"])
def test_a_name_with_lucene_punctuation_in_it_stays_one_phrase(name):
    #? the picker's box takes whatever is typed into it, so a stray quote must not end the phrase
    query = artist_query(name)
    assert query.count('"') % 2 == 0
    assert query.startswith("(artist:") and " OR alias:" in query


def test_an_artist_answers_to_every_name_they_have_ever_gone_by():
    names = artist_names(YE)
    assert names[0] == "Ye", "their current name leads"
    assert "Kanye West" in names and "Kanye Omari West" in names


def test_the_same_name_twice_is_listed_once():
    assert artist_names({"name": "Ye", "sort-name": "Ye", "aliases": [{"name": "ye"}]}) == ["Ye"]


def test_a_renamed_artist_is_found_by_the_name_on_disk():
    #? the fix: the folder says Kanye West because that is how the albums were credited
    assert answers_to(YE, "Kanye West") == "Kanye West"
    assert answers_to(YE, "kanye west") == "Kanye West", "and case is not the user's problem"
    assert answers_to(YE, "Ye") == "Ye", "their current name still matches"


def test_matching_stays_exact_and_never_fuzzy():
    #? a loose comparison would give back the guarantee that makes an automatic match safe at all
    assert answers_to(YE, "Kanye") == "Kanye", "an alias in full is a match"
    assert answers_to(YE, "Kany") == ""
    assert answers_to(YE, "Kanye West Tribute Band") == ""
    assert answers_to(YE, "") == "" and answers_to(None, "Ye") == ""


def test_how_a_name_was_typed_is_not_a_difference():
    """
    MusicBrainz sets names properly; folders and taggers do not.

    JAY-Z is "JAŸ‐Z" in MusicBrainz and credited "Jay‐Z", both with a U+2010 HYPHEN, while any
    folder anyone typed has a plain hyphen-minus. MusicBrainz's own index folds these - it
    answers the search with score 100 - so only this comparison was missing them.
    """
    jay = {"id": "jz", "name": "JA\u0178\u2010Z", "score": 100,
           "aliases": [{"name": "Jay\u2010Z", "type": "Artist name"}]}
    assert answers_to(jay, "Jay-Z") == "JA\u0178\u2010Z"

    assert answers_to({"name": "Mot\u00f6rhead"}, "Motorhead") == "Mot\u00f6rhead"
    assert answers_to({"name": "Bj\u00f6rk"}, "BJORK") == "Bj\u00f6rk"
    assert answers_to({"name": "Guns N\u2019 Roses"}, "Guns N' Roses") == "Guns N\u2019 Roses"


def test_folding_a_spelling_is_not_the_same_as_matching_loosely():
    #? it still has to be the WHOLE name - the guard this runs behind is what makes an automatic
    #? match safe, and a fuzzy comparison would hand that back
    assert answers_to({"name": "Bj\u00f6rk"}, "Bjork Gudmundsdottir") == ""
    assert answers_to({"name": "Mot\u00f6rhead"}, "Motor") == ""


def test_a_tribute_band_does_not_answer_to_the_artist_it_covers():
    #? what the old query actually returned first, and what must never resolve automatically
    tribute = {"id": "t1", "name": "Kanye West Tribute Band", "score": 100}
    assert answers_to(tribute, "Kanye West") == ""


def test_also_known_as_leaves_out_the_name_they_go_by_now():
    #? it read "Ye, KanYeWest, Donda, Kanye, ..." - their own name first, then two typos
    assert "Ye" not in artist_facts(YE)["aliases"]


def test_the_names_they_are_credited_under_lead_the_misspellings():
    aliases = artist_facts(YE)["aliases"]
    assert aliases[0] == "Kanye West"
    assert aliases.index("Kanye") < aliases.index("Kayne West"), "a real name beats a search hint"


# ---------------------------------------------------------------- which folder is the artist's

def test_the_artist_folder_is_the_one_their_albums_share():
    assert artist_folder([f"{ARTIST}/Jackpot Juicer (2022)", f"{ARTIST}/Afterburner (2020)"])["path"] == ARTIST


def test_albums_in_two_places_have_no_one_folder():
    found = artist_folder(["A/one", "B/two"])
    assert found["path"] is None and "different folders" in found["problem"]


def test_an_album_at_the_top_of_the_library_would_make_the_root_the_artist():
    #? and one artist's picture would land at the top of the whole library
    found = artist_folder(["Some Album"])
    assert found["path"] is None and "top of the library" in found["problem"]


def test_an_artist_with_no_albums_has_no_folder():
    assert artist_folder([])["path"] is None


# ---------------------------------------------------------------- planning the write

def test_a_plan_says_what_is_missing_and_leaves_what_is_there(tmp_path):
    directory = seed_artist(tmp_path)
    (directory / "artist.jpg").write_bytes(b"already here")

    plan = plan_artist_art(ARTIST, ["thumb", "banner"], str(tmp_path))
    actions = {f["kind"]: f["action"] for f in plan["files"]}

    assert actions == {"thumb": "keep", "banner": "write"}
    assert not plan["problems"]


def test_an_existing_picture_is_only_overwritten_when_asked(tmp_path):
    directory = seed_artist(tmp_path)
    (directory / "artist.png").write_bytes(b"chosen by hand")

    assert plan_artist_art(ARTIST, ["thumb"], str(tmp_path))["files"][0]["action"] == "keep"
    replacing = plan_artist_art(ARTIST, ["thumb"], str(tmp_path), replace=True)
    assert replacing["files"][0]["action"] == "replace"
    #? and it knows which file it would be replacing, whatever extension that one has
    assert replacing["files"][0]["existing"] == "artist.png"


def test_a_folder_of_tracks_is_an_album_and_is_refused(tmp_path):
    """The one that would land pictures among an album's files, where other readers use them."""
    seed_artist(tmp_path)
    album = f"{ARTIST}/Jackpot Juicer (2022)"

    plan = plan_artist_art(album, ["thumb"], str(tmp_path))
    assert plan["problems"] and "album rather than an artist" in plan["problems"][0]


def test_the_library_root_is_not_an_artist(tmp_path):
    seed_artist(tmp_path)
    assert "root" in plan_artist_art(".", ["thumb"], str(tmp_path))["problems"][0]


@pytest.mark.parametrize("path", ["../outside", "../../etc", f"{ARTIST}/../../elsewhere", ""])
def test_a_path_out_of_the_library_is_refused(tmp_path, path):
    seed_artist(tmp_path)
    (tmp_path.parent / "outside").mkdir(exist_ok=True)
    assert plan_artist_art(path, ["thumb"], str(tmp_path))["problems"]


def test_a_symlink_pointing_out_of_the_library_is_refused(tmp_path):
    seed_artist(tmp_path)
    outside = tmp_path.parent / "somewhere-else"
    outside.mkdir(exist_ok=True)
    (tmp_path / "Escape").symlink_to(outside, target_is_directory=True)

    assert plan_artist_art("Escape", ["thumb"], str(tmp_path))["problems"]


def test_a_kind_deadwax_does_not_write_is_ignored(tmp_path):
    seed_artist(tmp_path)
    assert plan_artist_art(ARTIST, ["mascot"], str(tmp_path))["problems"] == ["no images asked for"]


# ---------------------------------------------------------------- writing

def test_a_dry_run_writes_nothing(tmp_path, monkeypatch):
    directory = seed_artist(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    plan = plan_artist_art(ARTIST, ["thumb"], str(tmp_path))
    results = execute_artist_art(plan, {"thumb": (b"\xff\xd8\xff bytes", "image/jpeg")})

    assert results["dry_run"] and results["written"] == ["artist.jpg"]
    assert not (directory / "artist.jpg").exists()


def test_applying_writes_the_file_navidrome_reads(tmp_path, monkeypatch):
    directory = seed_artist(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    plan = plan_artist_art(ARTIST, ["thumb", "banner"], str(tmp_path))
    results = execute_artist_art(plan, {
        "thumb": (b"\xff\xd8\xff square", "image/jpeg"),
        "banner": (b"\x89PNG banner", "image/png"),
    }, mode="apply")

    assert sorted(results["written"]) == ["artist.jpg", "banner.png"]
    #? `artist.*` with no configuration at all is what Navidrome looks for
    assert (directory / "artist.jpg").read_bytes() == b"\xff\xd8\xff square"
    assert ARTIST_ART_STEMS["thumb"] == "artist"


def test_replacing_does_not_leave_the_old_extension_behind(tmp_path, monkeypatch):
    """Both would match `artist.*`, and which one a reader picks is then a coin toss."""
    directory = seed_artist(tmp_path)
    (directory / "artist.png").write_bytes(b"the old one")
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    plan = plan_artist_art(ARTIST, ["thumb"], str(tmp_path), replace=True)
    execute_artist_art(plan, {"thumb": (b"\xff\xd8\xff new", "image/jpeg")}, mode="apply")

    assert (directory / "artist.jpg").exists()
    assert not (directory / "artist.png").exists()


def test_nothing_is_written_for_a_plan_that_could_not_be_made(tmp_path, monkeypatch):
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    plan = plan_artist_art("../outside", ["thumb"], str(tmp_path))

    results = execute_artist_art(plan, {"thumb": (b"bytes", "image/jpeg")}, mode="apply")
    assert results["written"] == [] and results["problems"]


def test_containment_is_rechecked_at_the_write_not_trusted_from_the_plan(tmp_path, monkeypatch):
    """A plan is a list of file operations; one that arrived over the wire is not evidence."""
    seed_artist(tmp_path)
    plan = plan_artist_art(ARTIST, ["thumb"], str(tmp_path))

    elsewhere = tmp_path.parent / "another-library"
    elsewhere.mkdir(exist_ok=True)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(elsewhere))

    results = execute_artist_art(plan, {"thumb": (b"bytes", "image/jpeg")}, mode="apply")
    assert results["written"] == [] and "not inside the library" in results["problems"][0]


def test_a_picture_that_could_not_be_fetched_is_skipped_not_written_empty(tmp_path, monkeypatch):
    directory = seed_artist(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    plan = plan_artist_art(ARTIST, ["thumb", "banner"], str(tmp_path))
    results = execute_artist_art(plan, {"thumb": (b"\xff\xd8\xff ok", "image/jpeg")}, mode="apply")

    assert results["written"] == ["artist.jpg"]
    assert any("banner" in s for s in results["skipped"])
    assert not (directory / "banner.jpg").exists()


# ---------------------------------------------------------------- the routes

def fake_request(store=None, musicbrainz=None):
    state = SimpleNamespace()
    if store is not None:
        state.store = store
    if musicbrainz is not None:
        state.musicbrainz_client = musicbrainz
    return SimpleNamespace(app=SimpleNamespace(state=state))


def test_an_artist_nobody_has_is_a_404(tmp_path, monkeypatch):
    import asyncio

    from src.routes.library import artist as artist_route

    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    seed_artist(tmp_path)

    with pytest.raises(HTTPException) as refused:
        asyncio.run(artist_route(fake_request(), name="Nobody At All"))

    assert refused.value.status_code == 404


def test_the_preview_says_what_is_already_on_disk(tmp_path, monkeypatch):
    """
    The picker draws "that one is already there" from this, and it was missing.

    The interface's own type said the field was there, so nothing complained until the dialog
    read it and threw - a payload that disagrees with the type describing it is invisible until
    something touches the missing half.
    """
    import asyncio

    from src.routes import library as routes

    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    directory = seed_artist(tmp_path)
    (directory / "artist.jpg").write_bytes(b"already here")

    async def fake_get_artist(mbid):
        return {"id": mbid, "name": ARTIST}

    async def fake_candidates(artist):
        return []

    monkeypatch.setattr(routes.artist_images_client, "candidates", fake_candidates)

    body = routes.ArtistImagesRequest(artist=ARTIST, artist_mbid="abc")
    request = fake_request(musicbrainz=SimpleNamespace(get_artist=fake_get_artist))

    answer = asyncio.run(routes.artist_images_preview(request, body))

    assert answer["art"] == {"thumb": "artist.jpg"}
    #? and every field the picker reads is present, not merely most of them
    for key in ("art", "best", "candidates", "kinds", "plan", "has_key", "problems"):
        assert key in answer, f"the preview is missing {key}, which the dialog reads"


def test_applying_refuses_a_picture_the_sources_never_offered(tmp_path, monkeypatch):
    """
    The one that keeps this endpoint from being a fetcher for whatever it is told.

    Without it, `choices` would name any URL - inside this container's network, or on the host -
    and deadwax would GET it and write the answer into the library under a name other tools
    read. So apply recomputes the candidate list and only honours a URL that is in it, exactly
    as it recomputes the plan rather than accepting one back.
    """
    import asyncio

    from src.routes import library as routes

    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    directory = seed_artist(tmp_path)

    async def fake_get_artist(mbid):
        return {"id": mbid, "name": ARTIST}

    async def fake_candidates(artist):
        return [{"kind": "thumb", "url": "https://r2.theaudiodb.com/real.jpg",
                 "preview": "https://r2.theaudiodb.com/real.jpg", "source": "theaudiodb", "label": "Thumb"}]

    async def must_not_fetch(url):
        raise AssertionError(f"fetched {url}, which was never offered")

    monkeypatch.setattr(routes.artist_images_client, "candidates", fake_candidates)
    monkeypatch.setattr(routes.artist_images_client, "fetch", must_not_fetch)

    body = routes.ArtistImagesRequest(
        artist=ARTIST,
        artist_mbid="16456fed-c9f2-4adf-b6ea-97b648c474d2",
        choices={"thumb": "http://192.168.1.1/admin/backup.jpg"},
    )
    request = fake_request(musicbrainz=SimpleNamespace(get_artist=fake_get_artist))

    with pytest.raises(HTTPException) as refused:
        asyncio.run(routes.artist_images_apply(request, body))

    assert refused.value.status_code == 400
    #? and it says WHY, rather than "no images asked for" - which would be true of the plan and
    #? a lie about the request
    assert "not one of this artist's own pictures" in refused.value.detail
    assert not (directory / "artist.jpg").exists()


def test_a_library_credited_to_their_old_name_still_resolves_to_them(tmp_path, monkeypatch):
    """
    The whole point, at the level the page actually works.

    A library filed before v0.6.15 carries no artist ids, so the only key is the folder name -
    which is the CREDIT, and for anyone who has renamed that is now an alias. This used to
    resolve to nothing at all, and offered a tribute band as the first thing to click instead.
    """
    import asyncio

    from src.routes.library import _resolve_artist_mbid

    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    album = tmp_path / "Kanye West" / "Graduation (2007)"
    write_flac(album / "01 - Good Morning.flac", title="Good Morning", album="Graduation",
               albumartist="Kanye West", artist="Kanye West", date="2007")

    async def fake_search(name, limit=5):
        #? what the live API answers for (artist:"Kanye West" OR alias:"Kanye West")
        return {"artists": [YE, {"id": "tribute", "name": "Kanye West Tribute Band", "score": 77}]}

    mbid, source, matches = asyncio.run(_resolve_artist_mbid(
        fake_request(musicbrainz=SimpleNamespace(search_artists=fake_search)),
        "Kanye West", [{"path": "Kanye West/Graduation (2007)"}], None,
    ))

    assert mbid == YE["id"] and source == "search"
    #? and the row says which of their names it matched, or the answer "Ye" explains nothing
    assert matches[0]["matched_as"] == "Kanye West"
    assert matches[1]["matched_as"] == "", "the tribute band matched nothing, it merely scored"


def test_two_artists_answering_to_one_name_is_still_refused(tmp_path, monkeypatch):
    """
    Matching on aliases must not weaken the guard it runs behind.

    More names to match means MORE artists can tie, not fewer - and a tie is refused, because
    the cost of picking wrong is another band's photograph in this band's folder.
    """
    import asyncio

    from src.routes.library import _resolve_artist_mbid

    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    async def fake_search(name, limit=5):
        return {"artists": [
            {"id": "grunge", "name": "Nirvana", "score": 100,
             "disambiguation": "1980s-1990s US grunge band"},
            {"id": "uk", "name": "Nirvana", "score": 97, "disambiguation": "60s band from the UK"},
        ]}

    mbid, source, matches = asyncio.run(_resolve_artist_mbid(
        fake_request(musicbrainz=SimpleNamespace(search_artists=fake_search)),
        "Nirvana", [], None,
    ))

    assert mbid is None and source is None
    assert len(matches) == 2, "and both are offered as a choice instead"
