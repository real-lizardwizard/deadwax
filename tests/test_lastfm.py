"""
Last.fm's answers parsed, and an artist's top songs folded (2.1.41, S2 - notes/lastfm.md): src/lastfm.py artist_info(),
top_tracks(), top_songs(), count(), lastfm_url() and artist_answer() - and (2.1.43, S4) similar_artists(), similar_of(),
top_albums(), mbid_of() and similarity().

THE ANSWERS ARE LAST.FM'S OWN: tests/fixtures/lastfm/recorded/, written by tests/fixtures/lastfm/record.py on
2026-11-25 (James's key; checked to hold none of it) - ANSWERS below. The tests over those files assert what holds for
any answer (the fold's properties), so a recording made again passes them too; one test pins what the fold made of
these recordings (test_the_recorded_answers_fold_to_these_songs), which a new recording changes. What no recording
shows - a song twice by case, a feature, a remix, an empty name, a count missing or in words, one track given as an
object, a plain-http address - is held by tests with their answers inline, SHAPED from Last.fm's API pages (read
2026-11-24) and marked so. And one answer was kept from a first run whose key Last.fm refused: REFUSED_INVALID_KEY.
"""

import hashlib
import json
import sys
import unicodedata
from pathlib import Path

import pytest

from src.lastfm import (ANSWERED_NAME_MAX, BIO_MAX, CONTENT_BYTES, COUNT_DIGITS, LASTFM_SHAPE, LIST_ROW_BYTES, MBID,
                        NO_KEY_WHY, REPLACEMENT, SIMILAR_MAX, SUMMARY_BYTES, SUMMARY_LETTERS, TOP_ALBUMS_MAX,
                        TOP_SONGS, URL_MAX, VARIOUS_ARTISTS_MBID, Answer, Limited, NotKnown, Refused, Unreachable,
                        album_info, answerable, artist_answer, artist_info, classify, cleaned, count, lastfm_url,
                        match_key, mbid_of, name_key, no_key_answer, similar_artists, similar_of, similarity,
                        top_albums, top_songs, top_tracks, tracks_of, whole, without, written_size)
from src.lastfm_kept import ROW_MAX_BYTES, artist_key
from src.routes.lastfm import NAME_MAX

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "lastfm"
#? Last.fm's answers the tests read: record.py's, recorded 2026-11-25
ANSWERS = FIXTURES / "recorded"

#? the artists the fold is checked over, as record.py names their files - Portishead's for its three "- Live" takes,
#? the only repeats in these recordings (all three past its ten)
FOLDED = ("tame-impala.top-tracks.mbid", "tame-impala.top-tracks.name", "dance-gavin-dance.top-tracks.mbid",
          "dance-gavin-dance.top-tracks.name", "portishead.top-tracks.mbid", "misspelt.top-tracks")
INFOS = ("tame-impala.info.mbid", "tame-impala.info.name", "dance-gavin-dance.info.mbid", "dance-gavin-dance.info.name")
#? (2.1.43) artist.getSimilar's and artist.getTopAlbums' recordings: the three artists, by id and by name
SIMILARS = tuple(f"{slug}.similar.{by}" for slug in ("tame-impala", "dance-gavin-dance", "portishead")
                 for by in ("mbid", "name"))
ALBUM_LISTS = tuple(f"{slug}.top-albums.{by}" for slug in ("tame-impala", "dance-gavin-dance", "portishead")
                    for by in ("mbid", "name"))
#? each artist method as an artist page parses it - which kept_digest() runs over every recording of it
PARSES = {"artist.getinfo": artist_info, "artist.gettoptracks": top_tracks, "artist.getsimilar": similar_artists,
          "artist.gettopalbums": top_albums}


def envelope(name: str) -> dict:
    """One of ANSWERS' files: {method, params, status, headers, answer, ...} as record.py writes them."""
    return json.loads((ANSWERS / f"{name}.json").read_text(encoding="ascii"))


def answer(name: str):
    return envelope(name)["answer"]


def recorder():
    import importlib.util
    spec = importlib.util.spec_from_file_location("lastfm_record", FIXTURES / "record.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ----- the files are record.py's -------------------------------------------------------------------------------------

def test_every_answer_file_is_one_record_py_writes_asked_as_it_asks():
    """So pointing ANSWERS at recorded/ finds every file, and the stand-in Last.fm (tests/test_lastfm_routes.py),
    matching a request's parameters against each file's, matches the recorded ones the same way."""
    asked = {name: (method, params) for name, method, params in recorder().recordings()}
    files = sorted(path.stem for path in ANSWERS.glob("*.json"))
    assert set(files) == set(asked)
    for name in files:
        held = envelope(name)
        assert (held["method"], held["params"]) == asked[name], name
        assert {"recorded", "method", "params", "status", "headers", "answer"} <= set(held)
        assert "api_key" not in held["params"] and "<LASTFM_API_KEY>" not in json.dumps(held), name


def test_what_the_recordings_settle():
    """What the design rested on without having seen it (its 0.2), as the recordings answered on 2026-11-25."""
    for name in (path.stem for path in ANSWERS.glob("*.json")):
        held = envelope(name)
        #? every answer HTTP 200 - errors too - and no caching headers at all: the 7 days fresh stand
        assert held["status"] == 200, name
        assert not {"Cache-Control", "Expires"} & set(held["headers"]), name
    #? an artist Last.fm doesn't know - by name or by id - is HTTP 200 with error 6: NotKnown, kept as none
    for name in ("unknown-name.info", "unknown-name.top-tracks", "unknown-mbid.top-tracks"):
        held = envelope(name)
        assert held["answer"] == {"error": 6, "message": "The artist you supplied could not be found", "links": []}, name
        assert classify(held["status"], json.dumps(held["answer"]).encode(), 0.0) == NotKnown(
            "The artist you supplied could not be found")
    #? numbers as strings
    assert envelope("tame-impala.info.mbid")["answer"]["artist"]["stats"]["listeners"] == "4724887"
    #? a misspelling isn't corrected, autocorrect or not: Last.fm has a page under it, and answers that
    for name in ("misspelt.info", "misspelt.info.no-autocorrect"):
        artist = answer(name)["artist"]
        assert (artist["name"], artist["stats"]["listeners"], artist.get("mbid")) == ("Tame Impla", "9", None)
    #? Last.fm's order is by listeners, not plays - and deadwax keeps it
    tracks = tracks_of(answer("tame-impala.top-tracks.mbid"))
    listeners = [int(track["listeners"]) for track in tracks]
    plays = [int(track["playcount"]) for track in tracks]
    assert listeners == sorted(listeners, reverse=True) and plays != sorted(plays, reverse=True)
    #? (2.1.43) getTopAlbums carries `playcount` - a JSON number, not a string - and no `listeners`, unlike its API
    #? page's sample: so `counted` is "plays". Its order isn't by plays either (Deadbeat before Innerspeaker)
    for name in ALBUM_LISTS:
        albums = answer(name)["topalbums"]["album"]
        assert len(albums) == 50 and all(isinstance(album["playcount"], int) for album in albums), name
        assert not any("listeners" in album for album in albums), name
    plays = [album["playcount"] for album in answer("tame-impala.top-albums.mbid")["topalbums"]["album"]]
    assert plays != sorted(plays, reverse=True)
    #? getSimilar: 30 asked, 30 answered, `match` a string, Last.fm's order by it, the asked artist in `@attr` and
    #? never in the list; two of each thirty with no `mbid` at all
    for name in SIMILARS:
        listed = answer(name)["similarartists"]
        artists = listed["artist"]
        matches = [float(artist["match"]) for artist in artists]
        assert len(artists) == 30 and all(isinstance(artist["match"], str) for artist in artists), name
        assert matches == sorted(matches, reverse=True) and matches[0] == 1.0, name
        assert listed["@attr"]["artist"] not in [artist["name"] for artist in artists], name
        assert sum("mbid" not in artist for artist in artists) == 2, name


# ----- a real answer: an invalid key ----------------------------------------------------------------------------

#? RECORDED (2026-11-25, by record.py with a key Last.fm didn't accept - every one of that run's answers was this):
#? artist.getTopTracks for Tame Impala answered 403 with error 10. Copied out of recorded/, which the next run
#? overwrites, so this one stays
REFUSED_INVALID_KEY = FIXTURES / "refused-invalid-key.json"


def test_last_fms_real_invalid_key_answer_is_refused():
    """The one real answer in hand: error 10 comes with HTTP 403, and is a refusal - not Unreachable, which the 4xx
    alone would make it were the error code not read first."""
    held = json.loads(REFUSED_INVALID_KEY.read_text(encoding="ascii"))
    assert "recorded" in held and held["status"] == 403 and held["answer"]["error"] == 10
    outcome = classify(held["status"], json.dumps(held["answer"]).encode(), 1_764_000_000.0)
    assert outcome == Refused(10, "Invalid API key - You must be granted a valid key by last.fm", 1_764_000_000.0)


# ----- counts and addresses ------------------------------------------------------------------------------------------

@pytest.mark.parametrize("value, read", [
    ("2345678", 2345678), (" 2345678 ", 2345678), (2345678, 2345678), (0, 0), ("0", 0), (12.0, 12),
    (None, None), ("", None), ("n/a", None), ("2,345,678", None), ("-5", None), (-5, None), (1.5, None),
    (float("nan"), None), (float("inf"), None), (True, None), (False, None), ({}, None), ([], None),
    #? digits that aren't ASCII ones, and a string too long to be a count (int() refuses past 4300 digits)
    (chr(0x0661) + chr(0x0662), None), (chr(0xB2), None), ("9" * 19, None), ("9" * 5000, None),
])
def test_a_count_is_read_loosely_and_never_raises(value, read):
    assert count(value) == read


@pytest.mark.parametrize("link, passed", [
    ("https://www.last.fm/music/Tame+Impala", "https://www.last.fm/music/Tame+Impala"),
    (" https://www.last.fm/music/Tame+Impala\n", "https://www.last.fm/music/Tame+Impala"),
    ("https://last.fm/music/Cher/+wiki", "https://last.fm/music/Cher/+wiki"),
    ("https://WWW.LAST.FM/music/Cher", "https://WWW.LAST.FM/music/Cher"),
    ("http://www.last.fm/music/Tame+Impala", None),
    ("https://www.last.fm.example.com/music/x", None),
    ("https://notlast.fm/music/x", None),
    ("https://example.com/?u=https://www.last.fm/", None),
    ("javascript:alert(1)", None),
    ("https://[::1/", None),
    ("", None), (None, None), (42, None), ({"url": "https://www.last.fm/"}, None),
    #? a backslash, which a browser reads as "/" - so this is evil.example's page - and an @, which makes whatever is
    #? before it a user name: neither is in an address Last.fm makes
    ("https://evil.example\\.last.fm/x", None),
    ("https://www.last.fm/music/AC\\DC", None),
    ("https://evil.example@www.last.fm/x", None),
    ("https://www.last.fm@evil.example/x", None),
    #? printable ASCII only - Last.fm's are percent-encoded: a space, a letter it would have encoded, a control
    ("https://www.last.fm/music/Sigur Ros", None),
    ("https://www.last.fm/music/Bj" + chr(0xF6) + "rk", None),
    ("https://www.last.fm/music/Sigur%20R%C3%B3s", "https://www.last.fm/music/Sigur%20R%C3%B3s"),
    ("https://www.last.fm/music/x" + chr(0x7F), None),
    #? URL_MAX letters at most ("https://www.last.fm/music/" is 26)
    ("https://www.last.fm/music/" + "x" * (URL_MAX - 26), "https://www.last.fm/music/" + "x" * (URL_MAX - 26)),
    ("https://www.last.fm/music/" + "x" * (URL_MAX - 25), None),
])
def test_an_address_is_passed_on_only_when_it_is_https_on_last_fm(link, passed):
    assert lastfm_url(link) == passed


def test_every_address_in_the_recordings_passes():
    """The rule is narrow, not wrong: each of the 1,702 addresses Last.fm gave in the recordings (every `url` and
    `href`; its image addresses aside, which deadwax never passes on) is passed on as it is."""
    found: list[str] = []

    def walk(value):
        if isinstance(value, dict):
            for key, inner in value.items():
                if key in ("url", "href") and isinstance(inner, str):
                    found.append(inner)
                walk(inner)
        elif isinstance(value, list):
            for inner in value:
                walk(inner)

    for path in ANSWERS.glob("*.json"):
        walk(envelope(path.stem)["answer"])
    assert len(found) == 1702
    assert [link for link in found if lastfm_url(link) != link] == []


# ----- artist.getInfo ------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("name", INFOS)
def test_an_artists_info_is_its_address_its_listeners_and_its_bio(name):
    raw = answer(name)["artist"]
    parsed = artist_info(answer(name))
    assert set(parsed) == {"url", "listeners", "bio"}
    assert parsed["url"] == lastfm_url(raw["url"]) and parsed["url"].startswith("https://www.last.fm/music/")
    assert parsed["listeners"] == count(raw["stats"]["listeners"]) and isinstance(parsed["listeners"], int)
    assert set(parsed["bio"]) == {"summary", "content"}
    #? cut by letters alone: these bios are short of each field's bytes
    assert parsed["bio"]["summary"] == (raw["bio"]["summary"].strip()[:SUMMARY_LETTERS] or None)
    assert parsed["bio"]["content"] == (raw["bio"]["content"].strip()[:BIO_MAX] or None)


def test_listeners_as_a_string_a_number_absent_or_words_never_crash():
    #? SHAPED: getInfo's `stats` as Last.fm's page shows it (strings), and broken every way a field can be
    for stats, listeners in [({"listeners": "2345678"}, 2345678), ({"listeners": 612345}, 612345), ({}, None),
                             ({"listeners": "lots"}, None), ({"listeners": None}, None), ("n/a", None),
                             (None, None), ([1], None)]:
        assert artist_info({"artist": {"stats": stats}})["listeners"] == listeners


def test_an_info_answer_with_no_artist_in_it_is_none_and_a_sparse_one_is_nulls():
    for body in ({}, {"artist": "Tame Impala"}, {"artist": []}, [], "x", None):
        assert artist_info(body) is None
    assert artist_info({"artist": {}}) == {"url": None, "listeners": None, "bio": {"summary": None, "content": None}}


def test_a_long_bio_is_kept_cut():
    parsed = artist_info({"artist": {"bio": {"summary": "  short  ", "content": "x" * (BIO_MAX * 3)}}})
    assert parsed["bio"] == {"summary": "short", "content": "x" * BIO_MAX}
    parsed = artist_info({"artist": {"bio": {"summary": "y" * (SUMMARY_LETTERS * 3), "content": None}}})
    assert parsed["bio"] == {"summary": "y" * SUMMARY_LETTERS, "content": None}


@pytest.mark.parametrize("letter, size", [
    ("x", 1), ('"', 2), ("\\", 2), (chr(0x01), 6), (chr(0xE9), 6), (chr(0x416), 6), (chr(0x4E2D), 6),
    #? outside the BMP: a surrogate pair, 12 bytes
    (chr(0x1F3B8), 12), (chr(0x20000), 12),
])
def test_a_bio_is_cut_by_what_it_takes_written_too(letter, size):
    """A kept row is ASCII JSON: a letter outside ASCII is six bytes, one outside the BMP twelve. So each field is cut
    at its letters, then at its bytes - the summary keeps SUMMARY_LETTERS of any script in the BMP, which is all S3
    shows (descriptions.MAX_LETTERS)."""
    assert written_size(letter) == size
    assert written_size(letter * 7) == 7 * size
    bio = artist_info({"artist": {"bio": {"summary": letter * 20_000, "content": letter * 20_000}}})["bio"]
    for field, letters, most in (("summary", SUMMARY_LETTERS, SUMMARY_BYTES), ("content", BIO_MAX, CONTENT_BYTES)):
        assert bio[field] == letter * min(letters, most // size), field
        assert written_size(bio[field]) <= most
    from src.descriptions import MAX_LETTERS
    assert SUMMARY_LETTERS == MAX_LETTERS and SUMMARY_LETTERS * 6 <= SUMMARY_BYTES
    #? never a pair cut in half: a field is whole letters, read back as written
    assert json.loads(json.dumps(bio, ensure_ascii=True)) == bio


def test_a_getinfo_row_always_fits_the_keeping():
    """Whatever the script, the address and the name: the row src/lastfm_kept.py writes for getInfo - its JSON as it
    writes it, and its key - is never over ROW_MAX_BYTES, so an artist page's info is always kept."""
    #? the most bytes one letter of a name adds to its key: a letter NFKD leaves as it is adds at most its own 4
    #? (UTF-8); the 17,029 others, and "&", are tried. U+FDFA's 18 letters are the most, 33 bytes - and a space
    #? between letters at most 1 more
    changed = (chr(c) for c in range(sys.maxunicode + 1)
               if not 0xD800 <= c <= 0xDFFF and not unicodedata.is_normalized("NFKD", chr(c)))
    per_letter = max(4, len(name_key("&").encode()), *(len(name_key(c).encode()) for c in changed))
    assert per_letter == len(name_key(chr(0xFDFA)).encode()) == 33
    longest_key = len(artist_key("artist.getinfo", name="").encode()) + NAME_MAX * (per_letter + 1)
    assert len(artist_key("artist.getinfo", name=chr(0xFDFA) * NAME_MAX).encode()) <= longest_key
    link = "https://www.last.fm/music/" + "%" * (URL_MAX - 26)
    for letter in ("x", '"', chr(0x01), chr(0x416), chr(0x4E2D), chr(0x1F3B8)):
        body = {"artist": {"url": link, "stats": {"listeners": "9" * COUNT_DIGITS},
                           "bio": {"summary": letter * 20_000, "content": letter * 20_000}}}
        row = json.dumps(artist_info(body), ensure_ascii=True, separators=(",", ":"))
        assert artist_info(body)["url"] == link
        assert len(row) + longest_key <= ROW_MAX_BYTES, letter


# ----- artist.getTopTracks, and the fold --------------------------------------------------------------------------

@pytest.mark.parametrize("name", FOLDED)
def test_the_top_songs_are_last_fms_order_each_song_once_the_first_ten(name):
    """What holds for any answer, shaped or recorded: each song is the FIRST of Last.fm's tracks with its key, in
    Last.fm's order, every key once, no empty one, at most TOP_SONGS - and as many as there are distinct keys up to
    that; its title as Last.fm wrote it, its counts read loosely, its address only Last.fm's."""
    tracks = tracks_of(answer(name))
    songs = top_tracks(answer(name))["top_songs"]
    firsts: dict[str, int] = {}
    for at, track in enumerate(tracks):
        title = (track.get("name") or "").strip()
        if title and match_key(title):
            firsts.setdefault(match_key(title), at)
    assert len(songs) == min(TOP_SONGS, len(firsts))
    keys = [match_key(song["title"]) for song in songs]
    assert all(keys) and len(set(keys)) == len(keys)
    #? the first TOP_SONGS distinct songs, in Last.fm's order
    assert keys == sorted(firsts, key=firsts.get)[:TOP_SONGS]
    for song in songs:
        track = tracks[firsts[match_key(song["title"])]]
        assert song == {"title": track["name"].strip(), "playcount": count(track.get("playcount")),
                        "listeners": count(track.get("listeners")), "url": lastfm_url(track.get("url"))}


@pytest.mark.parametrize("name", FOLDED)
def test_the_artists_own_address_comes_with_the_top_tracks(name):
    tracks = tracks_of(answer(name))
    assert top_tracks(answer(name))["artist_url"] == lastfm_url(tracks[0]["artist"]["url"])


def songs_of(name: str) -> list[tuple[str, int]]:
    return [(song["title"], song["playcount"]) for song in top_tracks(answer(name))["top_songs"]]


def test_the_recorded_answers_fold_to_these_songs():
    """What the fold made of Last.fm's answers as recorded on 2026-11-25 - notes/lastfm.md has them too. A recording
    made again changes this, and only this. Tame Impala's and Dance Gavin Dance's top 50 hold no repeats at all;
    Portishead's hold three "- Live" takes, but at #34, #45 and #50. So in every recording the ten are Last.fm's first
    ten tracks as they are, and none shows the fold at work: the inline tests below do (test_ten_songs_not_ten_tracks,
    test_a_song_twice_is_kept_once_the_higher_ranked)."""
    assert songs_of("tame-impala.top-tracks.mbid") == songs_of("tame-impala.top-tracks.name") == [
        ("The Less I Know the Better", 51995043), ("Borderline", 31962438), ("New Person, Same Old Mistakes", 26439766),
        ("Let It Happen", 28648847), ("Feels Like We Only Go Backwards", 20213973), ("Eventually", 21238581),
        ("Nangs", 14543108), ("Elephant", 12610679), ("Yes I'm Changing", 13095273), ("Dracula", 14724597)]
    assert songs_of("dance-gavin-dance.top-tracks.mbid") == songs_of("dance-gavin-dance.top-tracks.name") == [
        ("We Own the Night", 4457241), ("Uneasy Hearts Weigh The Most", 3868294),
        ("And I Told Them I Invented Times New Roman", 2696274), ("Lemon Meringue Tie", 2355705),
        ("Death of a Strawberry", 2189374), ("Blue Dream", 2172176), ("It's Safe to Say You Dig the Backseat", 1265400),
        ("The Backwards Pumpkin Song", 1270182), ("Betrayed by the Game", 1412033),
        ("Open Your Eyes and Look North", 1004431)]
    for name in ("tame-impala.top-tracks.mbid", "dance-gavin-dance.top-tracks.mbid"):
        tracks = tracks_of(answer(name))
        assert len({match_key(track["name"]) for track in tracks}) == len(tracks) == 50
    #? Portishead's: "Glory Box - Live" (#34), "Sour times - Live" (#45) and "All Mine - Live" (#50), past the ten
    names = [track["name"] for track in tracks_of(answer("portishead.top-tracks.mbid"))]
    assert (names[33], names[44], names[49]) == ("Glory Box - Live", "Sour times - Live", "All Mine - Live")
    assert len({match_key(name) for name in names}) == 47
    for name in FOLDED:
        tracks = tracks_of(answer(name))
        assert [title for title, _ in songs_of(name)] == [track["name"].strip() for track in tracks[:TOP_SONGS]], name
    assert [title for title, _ in songs_of("portishead.top-tracks.mbid")] == [
        "Glory Box", "Roads", "Sour Times", "Mysterons", "Wandering Star", "Strangers", "It Could Be Sweet", "Numb",
        "The Rip", "All Mine"]
    #? the misspelling's own page: nine songs scrobbled under it, as people typed them
    assert [title for title, _ in songs_of("misspelt.top-tracks")][:4] == [
        "Feels Like We Only Go Backwards", "eventually", "Sundown Syndrome", "let it happen"]


def shaped_track(name, playcount="100", listeners="10", url=None):
    """SHAPED: one of artist.getTopTracks' tracks, as Last.fm's page shows one."""
    track = {"name": name, "playcount": playcount, "listeners": listeners, "mbid": "",
             "url": url or f"https://www.last.fm/music/Tame+Impala/_/{str(name).replace(' ', '+')}",
             "artist": {"name": "Tame Impala", "mbid": "", "url": "https://www.last.fm/music/Tame+Impala"},
             "@attr": {"rank": "1"}}
    return track


def titles(*names, **fields):
    return [song["title"] for song in top_songs([shaped_track(name, **fields) for name in names])]


def test_a_song_twice_is_kept_once_the_higher_ranked():
    assert titles("Let It Happen", "Elephant", "Let It Happen") == ["Let It Happen", "Elephant"]
    #? a case variant, an accent, other quotes: the same song - the first as it was written
    assert titles("The Less I Know the Better", "The Less I Know The Better") == ["The Less I Know the Better"]
    assert titles("Cest la vie", "C" + chr(0x2019) + "est la vie", "C'est la vie") == ["Cest la vie", "C" + chr(0x2019) + "est la vie"]
    assert titles("Desire Be Desire Go", "D" + chr(0xE9) + "sire Be Desire Go") == ["Desire Be Desire Go"]


def test_a_feature_or_a_take_is_the_song_and_a_remix_or_an_edit_a_song_of_its_own():
    assert titles("Lost in Yesterday", "Lost in Yesterday (feat. Someone Else)", "Lost in Yesterday ft. Someone Else",
                  "Lost in Yesterday [with Someone Else]") == ["Lost in Yesterday"]
    #? the feature first: it stands, as written, for the song without it below
    assert titles("Synergy (feat. Someone Else)", "Synergy") == ["Synergy (feat. Someone Else)"]
    assert titles("Let It Happen", "Let It Happen - 2015 Remaster", "Let It Happen - Live", "Let It Happen (Live)",
                  "Let It Happen (Remastered 2015)") == ["Let It Happen"]
    assert titles("Let It Happen", "Let It Happen (Soulwax Remix)", "Let It Happen - Radio Edit",
                  "Let It Happen - Acoustic", "Let It Happen - Demo") == [
        "Let It Happen", "Let It Happen (Soulwax Remix)", "Let It Happen - Radio Edit", "Let It Happen - Acoustic",
        "Let It Happen - Demo"]
    #? " with " unbracketed is a title's own words
    assert titles("Dancing with Myself", "Dancing") == ["Dancing with Myself", "Dancing"]


def test_a_track_with_no_name_or_a_name_that_keys_to_nothing_is_dropped():
    tracks = [shaped_track(name) for name in ("", "   ", "???", "Elephant")]
    tracks += [{"playcount": "1"}, {"name": None}, {"name": ["Elephant"]}]
    assert [song["title"] for song in top_songs(tracks)] == ["Elephant"]


def test_titles_are_as_last_fm_wrote_them_ends_trimmed():
    assert titles("  Let It Happen - 2015 Remaster  ") == ["Let It Happen - 2015 Remaster"]
    #? a number for a title (Last.fm's JSON gives strings; read loosely all the same)
    assert titles(1979) == ["1979"]


def test_no_more_than_ten():
    names = [f"Song {n}" for n in range(1, 30)]
    assert titles(*names) == names[:TOP_SONGS]
    assert TOP_SONGS == 10


def test_ten_songs_not_ten_tracks():
    """The fold runs over every track asked for (50), not the first ten: a repeat at #3 leaves room for #11."""
    names = [f"Song {n}" for n in range(1, 13)]
    names[2] = "Song 1 - Live"
    got = titles(*names)
    assert got == ["Song 1", "Song 2"] + [f"Song {n}" for n in range(4, 12)]
    assert len(got) == TOP_SONGS and "Song 11" in got and "Song 12" not in got


def test_a_top_songs_counts_and_address_are_read_loosely():
    [song] = top_songs([shaped_track("Elephant", playcount="1234", listeners=None,
                                     url="http://www.last.fm/music/Tame+Impala/_/Elephant")])
    assert song == {"title": "Elephant", "playcount": 1234, "listeners": None, "url": None}


def test_one_track_alone_none_and_junk():
    #? SHAPED: Last.fm's JSON is made from its XML, so one track can come as an object, not a list of one
    one = {"toptracks": {"track": shaped_track("Elephant"), "@attr": {"artist": "Tame Impala"}}}
    assert [song["title"] for song in top_tracks(one)["top_songs"]] == ["Elephant"]
    #? Last.fm knows the artist and lists nothing: [] - kept, a definite none
    for empty in ({"toptracks": {"track": []}}, {"toptracks": {}}, {"toptracks": {"track": "x"}}):
        assert top_tracks(empty) == {"artist_url": None, "top_songs": []}
    #? no top tracks in it at all: None - not an answer, never kept
    for junk in ({}, {"toptracks": []}, {"toptracks": "x"}, [], None):
        assert top_tracks(junk) is None
    assert top_tracks({"toptracks": {"track": [1, "x", None, shaped_track("Elephant")]}})["top_songs"][0]["title"] == "Elephant"


def test_the_kept_shape_has_not_moved():
    """Every kept row's key begins with LASTFM_SHAPE: a change to what artist_info, top_tracks, similar_artists or
    top_albums keep - or to the fold, kept folded - must bump it (the SCAN_FORMAT rule)."""
    assert set(top_tracks({"toptracks": {"track": [shaped_track("Elephant")]}})) == {"artist_url", "top_songs"}
    assert set(top_tracks({"toptracks": {"track": [shaped_track("Elephant")]}})["top_songs"][0]) == {
        "title", "playcount", "listeners", "url"}
    assert set(similar_artists(answer("tame-impala.similar.mbid"))) == {"artist", "similar"}
    assert set(similar_artists(answer("tame-impala.similar.mbid"))["similar"][0]) == {"name", "mbid", "match", "url"}
    assert set(top_albums(answer("tame-impala.top-albums.mbid"))) == {"top_albums"}
    assert set(top_albums(answer("tame-impala.top-albums.mbid"))["top_albums"][0]) == {"title", "mbid", "plays",
                                                                                        "counted"}


#? what each LASTFM_SHAPE keeps, as kept_digest() makes it. 2.1.41 kept nothing before it, so its shape is 1. A new
#? shape is added here, never put in place of the one before. 2 (2.1.43): the fold's dotted and dotless i, and
#? getSimilar's and getTopAlbums' rows - kept_digest() digests those too from 2, FOLD_CASES a dotted I, and each
#? case's match_key (the dotted I is past the fold's ten songs, so the fold alone never saw it); and (the review) a
#? lone surrogate kept whole, long lists fitted to LIST_ROW_BYTES, album titles that fold to nothing left out
KEPT_SHAPES = {
    1: "1aa7a8afb08b1358de968e031b32b2ba6aa36434a24b60a21d5967dc66b728cd",
    2: "147ccf482214a45ecc418fff7dfcc28160a31131719957167c66e940149ab9da",
}

#? a lone surrogate, as JSON's escape with no pair after it gives Python (2.1.43's review)
LONE = chr(0xD800)

#? SHAPED: titles the fold has to decide, beyond what the recordings hold - so the digest moves with match_key too.
#? (2.1.43) "Roads (LIVE)" with a dotted I is a song of its own, not "Roads" - as the TypeScript and the app key it
FOLD_CASES = ("Let It Happen", "Elephant", "Let It Happen - 2015 Remaster", "Let It Happen (Soulwax Remix)",
              "Lost in Yesterday (feat. Someone Else)", "Lost in Yesterday", "The Less I Know the Better",
              "The Less I Know The Better", "D" + chr(0xE9) + "sire Be Desire Go", "Desire Be Desire Go", "???", "",
              "Let It Happen - Radio Edit", "Dancing with Myself", "Dancing", "Glory Box - Live", "Glory Box",
              "Roads", "Mysterons", "Numb", "Strangers", "Roads (L" + chr(0x130) + "VE)",
              "Numb (l" + chr(0x131) + "ve)", "Mysterons (Rema" + chr(0x17F) + "tered)")

#? SHAPED (2.1.43): what getSimilar's and getTopAlbums' parses have to decide, beyond what the recordings hold
SIMILAR_CASES = {"similarartists": {"@attr": {"artist": "Tame Impala"}, "artist": [
    {"name": " Pond ", "mbid": "69AC44F7-C80D-47B4-9BC8-FCC758D209E6", "match": "1",
     "url": "https://www.last.fm/music/Pond"},
    {"name": "Various Artists", "mbid": "", "match": "0.9"},
    {"name": "VA", "mbid": VARIOUS_ARTISTS_MBID, "match": "0.8"},
    {"name": "", "mbid": "bca076a4-0ff5-43ae-b4c1-27ece7a0ca1c", "match": "0.7"},
    {"name": "GUM", "mbid": "bca076a4", "match": "nan", "url": "http://www.last.fm/music/GUM"},
    {"name": "Temples", "match": 0.5}, "x", {"name": 7, "match": "1.5"},
    {"name": "Po" + chr(0xD800) + "nd", "match": "0.4"}]}}
ALBUM_CASES = (
    #? as the API page's sample shows them: listeners alone
    {"topalbums": {"album": [{"name": "Currents", "listeners": "41", "mbid": ""},
                             {"name": "Lonerism", "listeners": 9}]}},
    #? both kinds in one list: plays, and the album with only listeners left out
    {"topalbums": {"album": [{"name": "Currents", "playcount": "12"}, {"name": "Lonerism", "listeners": "9"},
                             {"name": " ", "playcount": 3}, {"name": "Innerspeaker", "playcount": "lots"}]}},
    {"topalbums": {"album": {"name": "Currents", "playcount": 5}}},
    {"topalbums": {"album": [{"name": "Currents"}]}},
    #? (2.1.43's review) titles that fold to nothing left out; a lone surrogate kept as U+FFFD
    {"topalbums": {"album": [{"name": "(null)", "playcount": 9}, {"name": "( )", "playcount": 8},
                             {"name": "Curr" + chr(0xDC00) + "ents", "playcount": 7}]}},
)


def kept_digest() -> str:
    """What src/lastfm.py keeps, digested: each artist method parsed (and folded) over every recording of it, the
    fold over FOLD_CASES and each one's match_key, the similar and album cases, a bio cut by its bytes, and TOP_SONGS
    and the caps."""
    made = {
        "limits": [TOP_SONGS, BIO_MAX, SUMMARY_LETTERS, CONTENT_BYTES, SUMMARY_BYTES, URL_MAX, COUNT_DIGITS,
                   SIMILAR_MAX, TOP_ALBUMS_MAX, LIST_ROW_BYTES, ANSWERED_NAME_MAX],
        "recorded": {path.stem: PARSES[envelope(path.stem)["method"]](answer(path.stem))
                     for path in sorted(ANSWERS.glob("*.json")) if envelope(path.stem)["method"] in PARSES},
        "fold": top_songs([shaped_track(name) for name in FOLD_CASES]),
        #? every case's key too: the fold stops at TOP_SONGS, so a case past the tenth song moves only this
        "keys": [match_key(name) for name in FOLD_CASES],
        "similar": similar_artists(SIMILAR_CASES),
        "albums": [top_albums(body) for body in ALBUM_CASES],
        "bio": artist_info({"artist": {"bio": {"summary": chr(0x1F3B8) * 2000, "content": chr(0x416) * 5000}}}),
        #? (2.1.43's review) a lone surrogate, kept as U+FFFD; a long list kept as far as it fits
        "whole": artist_info({"artist": {"bio": {"summary": "A" + LONE + "B", "content": LONE}}}),
        "fitted": [similar_artists(similar_answer(*(shaped_similar(chr(0x1F3B8) * 400 + str(n)) for n in range(30)))),
                   top_albums({"topalbums": {"album": [{"name": chr(0x1F3B8) * 300 + str(n), "playcount": n}
                                                       for n in range(50)]}})],
    }
    return hashlib.sha256(json.dumps(made, sort_keys=True, ensure_ascii=True).encode()).hexdigest()


def test_what_is_kept_changes_only_with_lastfm_shape():
    """A kept row is read back as it was written, under a key beginning with LASTFM_SHAPE: one written by an older fold
    or parse, read as this one's, would be wrong for up to a week. So what they make is digested here and paired with
    the shape - a change to it without a bump fails."""
    made = kept_digest()
    assert LASTFM_SHAPE in KEPT_SHAPES, (
        f"LASTFM_SHAPE is {LASTFM_SHAPE}, which KEPT_SHAPES doesn't have: add {LASTFM_SHAPE}: {made!r} to it")
    assert KEPT_SHAPES[LASTFM_SHAPE] == made, (
        f"what Last.fm's answers are kept as has changed (the fold, the parse, TOP_SONGS or a cap) and LASTFM_SHAPE "
        f"is still {LASTFM_SHAPE}: bump LASTFM_SHAPE in src/lastfm.py, and add {LASTFM_SHAPE + 1}: {made!r} to "
        f"KEPT_SHAPES. (Only if nothing in src/lastfm.py changed - the recordings were made again - put this digest "
        f"in place of {LASTFM_SHAPE}'s.)")
    assert max(KEPT_SHAPES) == LASTFM_SHAPE


# ----- album.getInfo (2.1.42, S3 - the descriptions) ----------------------------------------------------------------

def test_an_albums_info_is_its_address_and_its_wiki():
    """Recorded: Dummy by Portishead, asked by its names with autocorrect - what descriptions.from_lastfm reads."""
    raw = answer("portishead.dummy.album-info")["album"]
    parsed = album_info(answer("portishead.dummy.album-info"))
    assert parsed == {"url": "https://www.last.fm/music/Portishead/Dummy",
                      "wiki": {"summary": raw["wiki"]["summary"].strip(), "content": raw["wiki"]["content"].strip()}}
    #? Last.fm's own mbid for it is not the release group's (48140466-cff6-3222-bd55-63c27e43190d): deadwax asks by
    #? names, and keeps no mbid
    assert raw["mbid"] == "00163fb1-5ab7-4fec-b0dd-a915e2722340"


def test_an_album_answer_with_no_album_in_it_is_none_and_a_sparse_one_is_nulls():
    for body in ({}, {"album": "Dummy"}, {"album": []}, [], "x", None):
        assert album_info(body) is None
    assert album_info({"album": {}}) == {"url": None, "wiki": {"summary": None, "content": None}}
    #? SHAPED: album.getInfo's page shows no `wiki` in its sample - an album with none is nulls, not a fault
    assert album_info({"album": {"name": "X", "url": "https://www.last.fm/music/A/X"}})["wiki"] == {
        "summary": None, "content": None}
    assert album_info({"album": {"url": "http://www.last.fm/music/A/X", "wiki": "x"}}) == {
        "url": None, "wiki": {"summary": None, "content": None}}


def test_an_albums_wiki_is_cut_as_a_bio_is():
    for letter, size in (("x", 1), (chr(0x4E2D), 6), (chr(0x1F3B8), 12)):
        wiki = album_info({"album": {"wiki": {"summary": letter * 20_000, "content": letter * 20_000}}})["wiki"]
        assert wiki == artist_info({"artist": {"bio": {"summary": letter * 20_000, "content": letter * 20_000}}})["bio"]
        assert written_size(wiki["summary"]) <= SUMMARY_BYTES and written_size(wiki["content"]) <= CONTENT_BYTES


#? what album_info keeps at each LASTFM_SHAPE, as album_digest() makes it - beside KEPT_SHAPES, not in it: album.getInfo
#? was first kept in 2.1.42, so no row of it was ever written before, at shape 1 or any other, and adding it bumps
#? nothing. From here it is held as the rest are: a change to it without a bump fails
KEPT_ALBUM_SHAPES = {
    1: "93640a62260d88063307bc86be90b2cd9f3e3bf904dec6861135a645c6a13de3",
    #? (2.1.43) album_info unchanged: the bump was the fold's and S4's
    2: "93640a62260d88063307bc86be90b2cd9f3e3bf904dec6861135a645c6a13de3",
}


def album_digest() -> str:
    """What src/lastfm.py keeps of album.getInfo, digested: the recorded answer, a wiki cut by its bytes and by its
    letters, and junk."""
    made = {
        "recorded": album_info(answer("portishead.dummy.album-info")),
        "wiki": album_info({"album": {"wiki": {"summary": chr(0x1F3B8) * 2000, "content": chr(0x416) * 5000}}}),
        "long": album_info({"album": {"wiki": {"summary": "x" * 2000, "content": "y" * 5000}}}),
        "sparse": [album_info(body) for body in ({"album": {}}, {"album": []}, {})],
    }
    return hashlib.sha256(json.dumps(made, sort_keys=True, ensure_ascii=True).encode()).hexdigest()


def test_what_is_kept_of_an_album_changes_only_with_lastfm_shape():
    """test_what_is_kept_changes_only_with_lastfm_shape's rule, for album.getInfo's rows."""
    made = album_digest()
    assert LASTFM_SHAPE in KEPT_ALBUM_SHAPES, (
        f"LASTFM_SHAPE is {LASTFM_SHAPE}, which KEPT_ALBUM_SHAPES doesn't have: add {LASTFM_SHAPE}: {made!r} to it")
    assert KEPT_ALBUM_SHAPES[LASTFM_SHAPE] == made, (
        f"what album.getInfo's answers are kept as has changed (album_info or a cap) and LASTFM_SHAPE is still "
        f"{LASTFM_SHAPE}: bump LASTFM_SHAPE in src/lastfm.py, and add {LASTFM_SHAPE + 1}: {made!r} to KEPT_ALBUM_SHAPES "
        f"(and KEPT_SHAPES its own). (Only if nothing in src/lastfm.py changed - the recording was made again - put "
        f"this digest in place of {LASTFM_SHAPE}'s.)")
    assert max(KEPT_ALBUM_SHAPES) == LASTFM_SHAPE


# ----- artist.getSimilar (2.1.43, S4) -------------------------------------------------------------------------------

TAME = "63aa26c3-d59b-4da4-84ac-716b54f1ef4d"


def test_mbid_is_the_routes_own_pattern():
    """lastfm.py imports no route, so it spells MusicBrainz's id itself: the very pattern the route takes."""
    from src.routes.search_musicbrainz import MBID_PATTERN
    assert "^" + MBID.pattern + "$" == MBID_PATTERN


@pytest.mark.parametrize("value, read", [
    ("69ac44f7-c80d-47b4-9bc8-fcc758d209e6", "69ac44f7-c80d-47b4-9bc8-fcc758d209e6"),
    #? Last.fm's, trimmed and lowercased: the same id, as the route and the app's MBID.of take one
    (" 69AC44F7-C80D-47B4-9BC8-FCC758D209E6 ", "69ac44f7-c80d-47b4-9bc8-fcc758d209e6"),
    #? any other shape: none - never a made-up page to open. The design's own sample's "a3b8..." among them
    ("", None), ("a3b8...", None), ("69ac44f7", None), ("69ac44f7-c80d-47b4-9bc8-fcc758d209e", None),
    ("69ac44f7-c80d-47b4-9bc8-fcc758d209e6a", None), ("{69ac44f7-c80d-47b4-9bc8-fcc758d209e6}", None),
    ("69ac44f7c80d47b49bc8fcc758d209e6", None), ("g9ac44f7-c80d-47b4-9bc8-fcc758d209e6", None),
    ("69ac44f7-c80d-47b4-9bc8-fcc758d209e6\n", "69ac44f7-c80d-47b4-9bc8-fcc758d209e6"),
    ("69ac44f7-c80d-47b4-9bc8-fcc758d209" + chr(0xFF45) + "6", None),
    (None, None), (42, None), (["69ac44f7-c80d-47b4-9bc8-fcc758d209e6"], None), (True, None),
])
def test_an_mbid_of_any_other_shape_is_none(value, read):
    assert mbid_of(value) == read


@pytest.mark.parametrize("value, read", [
    ("1", 1.0), ("0.706669", 0.706669), (" 0.5 ", 0.5), ("0", 0.0), (0.25, 0.25), (1, 1.0), (0, 0.0),
    ("1.5", None), ("-0.1", None), (-0.1, None), (2, None), ("nan", None), ("inf", None), (float("nan"), None),
    (float("inf"), None), ("", None), ("0,5", None), ("1e-3", None), ("1_0", None), (chr(0x0661), None),
    (None, None), (True, None), (False, None), ([0.5], None), ("9" * 30, None),
])
def test_a_match_is_read_loosely_and_never_raises(value, read):
    assert similarity(value) == read


@pytest.mark.parametrize("name", SIMILARS)
def test_similar_artists_are_last_fms_list_in_its_order(name):
    """What holds for any answer: Last.fm's own list, in its order, every field read as the parse reads it - at most
    SIMILAR_MAX, Various Artists and the nameless out."""
    listed = answer(name)["similarartists"]
    parsed = similar_artists(answer(name))
    assert parsed["artist"] == listed["@attr"]["artist"]
    assert parsed["similar"] == [
        {"name": artist["name"].strip(), "mbid": mbid_of(artist.get("mbid")), "match": float(artist["match"]),
         "url": lastfm_url(artist["url"])} for artist in listed["artist"]][:SIMILAR_MAX]
    assert len(parsed["similar"]) == SIMILAR_MAX == 30
    for artist in parsed["similar"]:
        assert artist["mbid"] is None or MBID.fullmatch(artist["mbid"])
        assert artist["url"].startswith("https://www.last.fm/music/")
    #? asked by id or by name, the same list
    slug = name.rsplit(".", 1)[0]
    assert similar_artists(answer(f"{slug}.mbid")) == similar_artists(answer(f"{slug}.name"))


def test_the_recorded_similar_artists():
    """What Last.fm answered on 2026-11-25 - notes/lastfm.md has them too. A recording made again changes this."""
    def first(name, n=5):
        return [(artist["name"], artist["match"]) for artist in similar_artists(answer(name))["similar"][:n]]
    assert first("tame-impala.similar.mbid") == [("Pond", 1.0), ("Melody's Echo Chamber", 0.706669), ("GUM", 0.655327),
                                                 ("Temples", 0.581892), ("The Holydrug Couple", 0.456447)]
    assert first("dance-gavin-dance.similar.mbid") == [("Royal Coda", 1.0), ("Eidola", 0.916765),
                                                       ("Secret Band", 0.912888), ("Wolf & Bear", 0.893214),
                                                       ("Emarosa", 0.717521)]
    assert first("portishead.similar.mbid") == [("The Funky Lowlives", 1.0), ("Pati Yang", 0.969213),
                                                ("Hird", 0.967942), ("Soma Sonic", 0.931464), ("Marsmobil", 0.922961)]
    #? the two of each thirty with no id: passed on with null, for the app to match by name (or leave out)
    nameless = {name: [a["name"] for a in similar_artists(answer(name))["similar"] if a["mbid"] is None]
                for name in ("tame-impala.similar.mbid", "dance-gavin-dance.similar.mbid", "portishead.similar.mbid")}
    assert nameless == {"tame-impala.similar.mbid": ["Melody's Echo Chamber", "King Gizzard & The Lizard Wizard"],
                        "dance-gavin-dance.similar.mbid": ["Hail The Sun", "Ghost Runner On Third"],
                        "portishead.similar.mbid": ["Martina Topley-Bird", "Dzihan & Kamien"]}


def similar_answer(*artists, attr="Tame Impala"):
    """SHAPED: artist.getSimilar's answer as its API page shows one."""
    return {"similarartists": {"artist": list(artists), "@attr": {"artist": attr}}}


def shaped_similar(name, mbid="", match="0.5"):
    """SHAPED: one of artist.getSimilar's artists."""
    return {"name": name, "mbid": mbid, "match": match,
            "url": f"https://www.last.fm/music/{str(name).replace(' ', '+')}", "image": [], "streamable": "0"}


def test_the_asked_artist_is_never_similar_to_themselves():
    """By the page's id, by the name it asked by, or by the name Last.fm answered for (each folded, so a case, a
    leading "The" or an aside are the same name): dropped. No recording lists the artist - these are SHAPED."""
    kept = similar_artists(similar_answer(
        shaped_similar("Impala, Tame", mbid=TAME.upper()), shaped_similar("Pond"), shaped_similar("TAME IMPALA"),
        shaped_similar("The Tame Impala"), shaped_similar("Tame Impala (AU)"), shaped_similar("Kevin Parker"),
        shaped_similar("GUM")))
    assert [a["name"] for a in similar_of(kept, TAME, "Tame Impala")] == ["Pond", "Kevin Parker", "GUM"]
    #? asked by id alone: the name Last.fm answered for drops them by name all the same
    assert [a["name"] for a in similar_of(kept, TAME, None)] == ["Pond", "Kevin Parker", "GUM"]
    #? asked by name alone: no id to know them by - the one listed under another name stays
    assert [a["name"] for a in similar_of(kept, None, "tame impala")] == ["Impala, Tame", "Pond", "Kevin Parker", "GUM"]
    #? the page asked by another of his names: that one dropped too, and Last.fm's own name's
    assert [a["name"] for a in similar_of(kept, None, "Kevin Parker")] == ["Impala, Tame", "Pond", "GUM"]
    #? a kept row with no name of Last.fm's: only what the page asked by
    bare = {"artist": None, "similar": kept["similar"]}
    assert [a["name"] for a in similar_of(bare, None, "Kevin Parker")] == [
        "Impala, Tame", "Pond", "TAME IMPALA", "The Tame Impala", "Tame Impala (AU)", "GUM"]


def test_a_name_that_folds_to_nothing_drops_nobody():
    """"!!!" (chk chk chk) folds to "": as the asked name it would otherwise drop every other such name."""
    kept = similar_artists(similar_answer(shaped_similar("!!!"), shaped_similar("???"), shaped_similar("Pond"),
                                          attr="!!!"))
    assert [a["name"] for a in similar_of(kept, None, "!!!")] == ["!!!", "???", "Pond"]
    assert [a["name"] for a in similar_of(kept, None, "...")] == ["!!!", "???", "Pond"]


def test_various_artists_and_the_nameless_are_never_similar():
    kept = similar_artists(similar_answer(
        shaped_similar("Various Artists"), shaped_similar("  various   artists "),
        shaped_similar("VA", VARIOUS_ARTISTS_MBID),
        shaped_similar(""), shaped_similar("   "), {"match": "1"}, {"name": None}, "Pond", 7, shaped_similar("Pond")))
    assert [a["name"] for a in kept["similar"]] == ["Pond"]


def test_no_more_than_thirty():
    names = [f"Band {n}" for n in range(45)]
    kept = similar_artists(similar_answer(*(shaped_similar(name) for name in names)))
    assert [a["name"] for a in kept["similar"]] == names[:SIMILAR_MAX]
    #? and a kept row read back is held to it too
    assert len(similar_of({"similar": [shaped_similar(name) for name in names]}, None, None)) == SIMILAR_MAX


def test_a_similar_artists_fields_are_read_loosely():
    [artist] = similar_artists(similar_answer({"name": " MGMT ", "mbid": "a3b8...", "match": "lots",
                                               "url": "http://www.last.fm/music/MGMT"}))["similar"]
    assert artist == {"name": "MGMT", "mbid": None, "match": None, "url": None}
    #? one artist alone, given as an object (Last.fm's JSON is made from its XML); a name given as a number
    assert similar_artists({"similarartists": {"artist": shaped_similar("MGMT")}})["similar"][0]["name"] == "MGMT"
    assert similar_artists(similar_answer(shaped_similar(1349)))["similar"][0]["name"] == "1349"


def test_a_similar_answer_with_none_or_junk():
    #? known, listing none: [] - kept, a definite none; no `@attr`: no name of Last.fm's to drop by
    for empty in ({"similarartists": {"artist": []}}, {"similarartists": {}}, {"similarartists": {"artist": "x"}}):
        assert similar_artists(empty) == {"artist": None, "similar": []}
    #? no similar artists in it at all: None - not an answer, never kept
    for junk in ({}, {"similarartists": []}, {"similarartists": "x"}, [], None, {"toptracks": {}}):
        assert similar_artists(junk) is None


def test_a_kept_similar_row_read_back_carefully():
    odd = {"artist": 7, "similar": [{"name": "Pond", "mbid": "nope", "match": 3, "url": "http://x/"}, "x", {"name": ""},
                                    {"name": "GUM", "mbid": VARIOUS_ARTISTS_MBID}]}
    assert similar_of(odd, None, None) == [{"name": "Pond", "mbid": None, "match": None, "url": None}]
    for junk in ({}, {"similar": "x"}, {"similar": None}):
        assert similar_of(junk, TAME, "Tame Impala") == []


# ----- artist.getTopAlbums (2.1.43, S4) -----------------------------------------------------------------------------

@pytest.mark.parametrize("name", ALBUM_LISTS)
def test_top_albums_are_last_fms_order_counted_by_plays(name):
    """Every recording's albums carry a playcount: each is passed on, in Last.fm's order, its plays its playcount."""
    albums = answer(name)["topalbums"]["album"]
    parsed = top_albums(answer(name))["top_albums"]
    assert parsed == [{"title": album["name"].strip(), "mbid": mbid_of(album.get("mbid")), "plays": album["playcount"],
                       "counted": "plays"} for album in albums][:TOP_ALBUMS_MAX]
    assert len(parsed) == TOP_ALBUMS_MAX == 50
    slug = name.rsplit(".", 1)[0]
    assert top_albums(answer(f"{slug}.mbid")) == top_albums(answer(f"{slug}.name"))


def test_the_recorded_top_albums():
    """What Last.fm answered on 2026-11-25 - notes/lastfm.md has them too. A recording made again changes this."""
    def first(name, n=4):
        return [(album["title"], album["plays"]) for album in top_albums(answer(name))["top_albums"][:n]]
    assert first("tame-impala.top-albums.mbid") == [("Currents", 197990342), ("The Slow Rush", 75865879),
                                                    ("Lonerism", 65345426), ("Deadbeat", 23596438)]
    assert first("portishead.top-albums.mbid") == [("Dummy", 64559236), ("Third", 26492622), ("Portishead", 21622377),
                                                   ("Roseland NYC Live", 6751781)]
    assert first("dance-gavin-dance.top-albums.mbid") == [("Downtown Battle Mountain", 13211300),
                                                          ("Instant Gratification", 11393457),
                                                          ("Dance Gavin Dance", 10451913),
                                                          ("Downtown Battle Mountain II", 7845171)]
    #? Dummy's album id is Last.fm's own, a release's (tests/test_lastfm.py's album.getInfo: not its release group)
    assert top_albums(answer("portishead.top-albums.mbid"))["top_albums"][0]["mbid"] == (
        "00163fb1-5ab7-4fec-b0dd-a915e2722340")
    with_ids = {name: sum(album["mbid"] is not None for album in top_albums(answer(name))["top_albums"])
                for name in ALBUM_LISTS if name.endswith(".mbid")}
    assert with_ids == {"tame-impala.top-albums.mbid": 38, "dance-gavin-dance.top-albums.mbid": 33,
                        "portishead.top-albums.mbid": 22}


def test_top_albums_without_a_playcount_are_counted_by_listeners_and_never_crash():
    """SHAPED - the design's fork: getTopAlbums' API page shows each album with listeners, not plays. With no
    playcount anywhere, the list is counted by listeners and says so; with neither, nothing to order by."""
    sample = {"topalbums": {"album": [{"name": "Currents", "listeners": "41000", "mbid": "", "url": "x"},
                                      {"name": "Lonerism", "listeners": 9000}, {"name": "Innerspeaker"}]}}
    assert top_albums(sample)["top_albums"] == [
        {"title": "Currents", "mbid": None, "plays": 41000, "counted": "listeners"},
        {"title": "Lonerism", "mbid": None, "plays": 9000, "counted": "listeners"}]
    for none in ({"topalbums": {"album": [{"name": "Currents"}, {"name": "Lonerism", "playcount": "lots",
                                                                  "listeners": None}]}},
                 {"topalbums": {"album": []}}, {"topalbums": {}}, {"topalbums": {"album": "x"}}):
        assert top_albums(none) == {"top_albums": []}


def test_one_count_for_the_whole_list():
    """Any album with a playcount makes the list's count plays: an album with only listeners is left out, never set
    beside plays as though it were them."""
    mixed = {"topalbums": {"album": [{"name": "Currents", "playcount": "12", "listeners": "3"},
                                     {"name": "Lonerism", "listeners": "900"}, {"name": "Slow Rush", "playcount": 7}]}}
    assert top_albums(mixed)["top_albums"] == [
        {"title": "Currents", "mbid": None, "plays": 12, "counted": "plays"},
        {"title": "Slow Rush", "mbid": None, "plays": 7, "counted": "plays"}]


def test_a_top_albums_fields_are_read_loosely():
    one = {"topalbums": {"album": {"name": "  Currents ", "playcount": " 5 ",
                                   "mbid": "031ECBDE-35E1-4D3A-917F-F89F31ACA1C9"}}}
    assert top_albums(one)["top_albums"] == [{"title": "Currents", "mbid": "031ecbde-35e1-4d3a-917f-f89f31aca1c9",
                                              "plays": 5, "counted": "plays"}]
    odd = {"topalbums": {"album": [{"name": "", "playcount": 9}, {"playcount": 9}, "x", None,
                                   {"name": 1979, "playcount": 1},
                                   {"name": "Dummy", "playcount": -3}, {"name": "Third", "playcount": 2.5},
                                   {"name": "Roads", "playcount": "9" * 30}]}}
    assert top_albums(odd)["top_albums"] == [{"title": "1979", "mbid": None, "plays": 1, "counted": "plays"}]
    names = [f"Album {n}" for n in range(70)]
    many = {"topalbums": {"album": [{"name": name, "playcount": n} for n, name in enumerate(names)]}}
    assert [album["title"] for album in top_albums(many)["top_albums"]] == names[:TOP_ALBUMS_MAX]
    #? no top albums in it at all: None - not an answer, never kept
    for junk in ({}, {"topalbums": []}, {"topalbums": "x"}, [], None):
        assert top_albums(junk) is None


def test_the_limits_are_what_the_route_and_the_recorder_ask():
    from src.routes import lastfm as route
    asked = {method: params for _, method, params in recorder().recordings()}
    assert route.SIMILAR_ASKED == str(SIMILAR_MAX) == asked["artist.getsimilar"]["limit"]
    assert route.TOP_ALBUMS_ASKED == str(TOP_ALBUMS_MAX) == asked["artist.gettopalbums"]["limit"]


# ----- what UTF-8 can carry, and what the keeping can keep (2.1.43's review) ---------------------------------------

def sendable(value) -> bool:
    """Whether the route's encoder (Starlette's JSONResponse: UTF-8, not ASCII) can send `value`."""
    try:
        json.dumps(value, ensure_ascii=False).encode("utf-8")
    except UnicodeEncodeError:
        return False
    return True


def test_a_lone_surrogate_is_never_kept_or_answered():
    """SHAPED: Last.fm's JSON could say "Po\\ud800nd" - a lone surrogate in Python, kept as it came, and every answer
    made from the row a 500 until it went stale. Each text the parses keep is whole: U+FFFD in its place."""
    odd, fixed = " Po" + LONE + "nd" + chr(0xDFFF) + " ", "Po" + REPLACEMENT + "nd" + REPLACEMENT
    assert not sendable(odd) and whole(odd.strip()) == fixed
    tracks = top_tracks({"toptracks": {"track": [{"name": odd, "playcount": "9"}]}})
    similar = similar_artists(similar_answer(shaped_similar(odd), attr=odd))
    albums = top_albums({"topalbums": {"album": [{"name": odd, "playcount": 9}]}})
    info = artist_info({"artist": {"bio": {"summary": odd, "content": odd * 3}}})
    wiki = album_info({"album": {"wiki": {"summary": odd, "content": odd}}})
    assert tracks["top_songs"][0]["title"] == similar["similar"][0]["name"] == similar["artist"] == fixed
    assert albums["top_albums"][0]["title"] == info["bio"]["summary"] == wiki["wiki"]["content"] == fixed
    assert all(map(sendable, (tracks, similar, albums, info, wiki)))
    #? a letter outside the BMP is one letter, never a surrogate: kept as it is
    assert whole(chr(0x1F3B8)) == chr(0x1F3B8) and json.loads('"\\ud83c\\udfb8"') == chr(0x1F3B8)


def test_a_kept_row_with_a_lone_surrogate_is_answered_whole():
    """A row is read back through the same checks: one written before the parse was whole is answered whole."""
    odd = "Po" + LONE + "nd"
    got = artist_answer(INFO, Answer({"top_songs": [{"title": odd}]}), Answer({"similar": [{"name": odd}]}),
                        Answer({"top_albums": [{"title": odd, "plays": 3, "counted": "plays"}]}), None)
    assert got["top_songs"][0]["title"] == got["similar"][0]["name"] == got["top_albums"][0]["title"] == (
        "Po" + REPLACEMENT + "nd")
    assert sendable(got)


def test_answerable_is_every_text_whole_and_nothing_else_touched():
    odd = "a" + LONE
    got = answerable({"x": [odd, {odd: (odd, 7, None, 1.5, True)}], "n": 3})
    assert got == {"x": ["a" + REPLACEMENT, {"a" + REPLACEMENT: ["a" + REPLACEMENT, 7, None, 1.5, True]}], "n": 3}
    assert sendable(got) and answerable(no_key_answer()) == no_key_answer()


def test_a_similar_and_an_albums_row_always_fit_the_keeping():
    """Whatever the names: thirty similar artists or fifty albums with names of letters outside the BMP (12 bytes
    each, written) are kept as far as they fit LIST_ROW_BYTES - the first of them, in Last.fm's order - and that, with
    the longest key a name of the route's NAME_MAX makes, is under ROW_MAX_BYTES. Never a row too big to keep."""
    from src.routes.lastfm import NAME_MAX
    assert ANSWERED_NAME_MAX == NAME_MAX
    #? the most a letter of a name adds to its key: 33 bytes (U+FDFA), a space at most 1 more -
    #? test_a_getinfo_row_always_fits_the_keeping
    for method in ("artist.getsimilar", "artist.gettopalbums"):
        longest_key = len(artist_key(method, name="").encode()) + NAME_MAX * (33 + 1)
        assert LIST_ROW_BYTES + longest_key <= ROW_MAX_BYTES, method

    def size(row):
        return len(json.dumps(row, ensure_ascii=True, separators=(",", ":")))

    star = chr(0x1F3B8)
    names = [star * 1000 + str(n) for n in range(SIMILAR_MAX)]
    full = similar_artists(similar_answer(*map(shaped_similar, names), attr=star * ANSWERED_NAME_MAX))
    assert full["artist"] == star * ANSWERED_NAME_MAX and size(full) <= LIST_ROW_BYTES
    kept = [artist["name"] for artist in full["similar"]]
    assert 0 < len(kept) < SIMILAR_MAX and kept == names[:len(kept)]
    #? one more would not have fitted
    more = {**full, "similar": full["similar"] + [{"name": names[len(kept)], "mbid": None, "match": 0.5,
                                                   "url": None}]}
    assert size(more) > LIST_ROW_BYTES
    #? the name Last.fm answered for, past the route's NAME_MAX: no name a page asks by, so not kept
    assert similar_artists(similar_answer(shaped_similar("Pond"), attr="x" * (ANSWERED_NAME_MAX + 1)))["artist"] is None

    titles = [star * 600 + str(n) for n in range(TOP_ALBUMS_MAX)]
    albums = top_albums({"topalbums": {"album": [{"name": title, "playcount": 9} for title in titles]}})
    assert size(albums) <= LIST_ROW_BYTES
    assert [album["title"] for album in albums["top_albums"]] == titles[:len(albums["top_albums"])]
    assert 0 < len(albums["top_albums"]) < TOP_ALBUMS_MAX
    #? one entry too big for any row: none of it - the list Last.fm gave is said as nothing rather than not kept
    assert top_albums({"topalbums": {"album": [{"name": star * 3000, "playcount": 9}]}}) == {"top_albums": []}
    #? the recordings are far under it: every entry kept
    for name in SIMILARS + ALBUM_LISTS:
        parsed = PARSES[envelope(name)["method"]](answer(name))
        assert size(parsed) < 6000 and len(parsed.get("similar", parsed.get("top_albums"))) in (30, 50), name


def test_an_album_title_that_folds_to_nothing_is_left_out():
    """SHAPED: "(null)" - and "( )", Sigur Ros's own album, and "!!!", the band's - fold to nothing (name_key drops a
    bracketed aside, and keeps letters and digits only), so the app could never meet them by title: left out, in the
    parse and read back. notes/lastfm.md "S4" says what that does to those albums."""
    titles = ["(null)", "( )", "[ ]", "!!!", "...", "Takk...", "Agaetis byrjun", "()", "1979"]
    parsed = top_albums({"topalbums": {"album": [{"name": title, "playcount": 9} for title in titles]}})
    assert [album["title"] for album in parsed["top_albums"]] == ["Takk...", "Agaetis byrjun", "1979"]
    #? the list's count is decided by the albums passed on: a "(null)" alone with plays decides nothing
    only = {"topalbums": {"album": [{"name": "(null)", "playcount": 9}, {"name": "Takk...", "listeners": 4}]}}
    assert top_albums(only)["top_albums"] == [{"title": "Takk...", "mbid": None, "plays": 4, "counted": "listeners"}]
    kept = artist_answer(INFO, TRACKS, SIMILAR, Answer({"top_albums": [
        {"title": "(null)", "plays": 9, "counted": "plays"}, {"title": "Takk...", "plays": 3, "counted": "plays"}]}),
        None)
    assert [album["title"] for album in kept["top_albums"]] == ["Takk..."]


# ----- the answer ----------------------------------------------------------------------------------------------------

INFO = Answer({"url": "https://www.last.fm/music/Tame+Impala", "listeners": 2345678,
               "bio": {"summary": None, "content": None}})
TRACKS = Answer({"artist_url": "https://www.last.fm/music/Tame+Impala",
                 "top_songs": [{"title": "Elephant", "playcount": 5, "listeners": 2,
                                "url": "https://www.last.fm/music/Tame+Impala/_/Elephant"}]})
SIMILAR = Answer({"artist": "Tame Impala", "similar": [
    {"name": "Pond", "mbid": "69ac44f7-c80d-47b4-9bc8-fcc758d209e6", "match": 1.0,
     "url": "https://www.last.fm/music/Pond"},
    {"name": "Tame Impala", "mbid": None, "match": 0.9, "url": None}]})
ALBUMS = Answer({"top_albums": [{"title": "Currents", "mbid": "031ecbde-35e1-4d3a-917f-f89f31aca1c9", "plays": 12,
                                 "counted": "plays"}]})
PARTS = (INFO, TRACKS, SIMILAR, ALBUMS)
REFUSAL = Refused(10, "Invalid API key - You must be granted a valid key by last.fm", 1_764_000_000.0)


def test_an_answer_with_every_part():
    assert artist_answer(*PARTS, None, mbid=TAME, name="Tame Impala") == {
        "enabled": True, "unavailable": False, "why": None, "url": "https://www.last.fm/music/Tame+Impala",
        "listeners": 2345678, "top_songs": TRACKS.body["top_songs"], "similar": SIMILAR.body["similar"][:1],
        "top_albums": ALBUMS.body["top_albums"]}


def test_one_part_failing_or_late_leaves_the_others():
    fields = {1: "top_songs", 2: "similar", 3: "top_albums"}
    for failed in (Unreachable("HTTP 500"), Limited("error 29"), None):
        got = artist_answer(failed, TRACKS, SIMILAR, ALBUMS, None)
        assert (got["enabled"], got["unavailable"], got["why"]) == (True, True, None)
        assert got["listeners"] is None and got["top_songs"] == TRACKS.body["top_songs"]
        #? the address from the top tracks' artist, getInfo gone
        assert got["url"] == "https://www.last.fm/music/Tame+Impala"
        for at, field in fields.items():
            parts = list(PARTS)
            parts[at] = failed
            got = artist_answer(*parts, None)
            assert got["unavailable"] and got[field] is None and got["listeners"] == 2345678, field
            assert all(got[other] for other in fields.values() if other != field), field


def test_an_artist_last_fm_doesnt_know_is_nothing_and_nothing_failed():
    assert artist_answer(NotKnown(), NotKnown(), NotKnown(), NotKnown(), None) == {
        "enabled": True, "unavailable": False, "why": None, "url": None, "listeners": None, "top_songs": None,
        "similar": None, "top_albums": None}
    #? known, but listing nothing
    got = artist_answer(INFO, Answer({"artist_url": None, "top_songs": []}), Answer({"artist": None, "similar": []}),
                        Answer({"top_albums": []}), None)
    assert (got["top_songs"], got["similar"], got["top_albums"]) == ([], [], [])


def test_refused_with_nothing_kept_is_off_and_says_why():
    got = artist_answer(REFUSAL, REFUSAL, REFUSAL, REFUSAL, REFUSAL)
    assert got == {"enabled": False, "unavailable": True,
                   "why": "Last.fm refused deadwax's API key (error 10: Invalid API key - You must be granted a valid "
                          "key by last.fm) - check LASTFM_API_KEY in Server settings > Connections: it's the API key, "
                          "not the shared secret.",
                   "url": None, "listeners": None, "top_songs": None, "similar": None, "top_albums": None}
    #? something kept: answered, and still why
    got = artist_answer(REFUSAL, REFUSAL, SIMILAR, REFUSAL, REFUSAL)
    assert got["enabled"] and got["similar"] and got["why"].startswith("Last.fm refused")


def test_the_key_is_taken_out_in_any_case():
    """Last.fm's keys are hex, and a message could quote one back in capitals: taken out all the same."""
    key = "5e17e1d0b5e17e1d0b5e17e1d0b5e1ab"
    for echoed in (key, key.upper(), key[:16].upper() + key[16:]):
        assert without(f"bad key {echoed}!", key) == "bad key (the key)!"
        assert cleaned(f"Invalid API key ({echoed}) - {echoed}", key) == "Invalid API key ((the key)) - (the key)"
    #? a key set in capitals, quoted back in lower case
    assert without(f"bad key {key}", key.upper()) == "bad key (the key)"
    #? the key is text, never a pattern
    assert without("a.b a+b", "a.b") == "(the key) a+b"
    assert without("nothing to take", None) == without("nothing to take", "") == "nothing to take"


def test_no_key():
    assert no_key_answer() == {"enabled": False, "unavailable": False, "why": NO_KEY_WHY, "url": None,
                               "listeners": None, "top_songs": None, "similar": None, "top_albums": None}
    assert NO_KEY_WHY == ("No Last.fm API key is set - add LASTFM_API_KEY in Server settings > Connections (a free key "
                          "from last.fm/api/account/create).")


def test_a_kept_row_read_back_carefully():
    """A kept row is deadwax's own, but read as carefully as an answer: a bad address or count never passed on."""
    odd = Answer({"url": "http://evil.example/", "listeners": "12", "top_songs": "x"})
    albums = Answer({"top_albums": [{"title": "Currents", "plays": "12", "counted": "listeners", "mbid": "x"},
                                    {"title": "Lonerism", "plays": 3, "counted": "plays"}, {"title": "", "plays": 1},
                                    {"title": "Third", "plays": None, "counted": "listeners"},
                                    {"title": "Dummy", "plays": 4, "counted": "streams"}, "x",
                                    {"title": "Roads", "plays": 9, "counted": "listeners"}]})
    got = artist_answer(odd, Answer({"top_songs": [{"title": "", }, "x", {"title": "Elephant", "url": "http://x/"}]}),
                        Answer({"similar": "x"}), albums, None)
    assert got["url"] is None and got["listeners"] == 12
    assert got["top_songs"] == [{"title": "Elephant", "playcount": None, "listeners": None, "url": None}]
    assert got["similar"] == []
    #? one kind for the list: the first readable album's
    assert got["top_albums"] == [{"title": "Currents", "mbid": None, "plays": 12, "counted": "listeners"},
                                 {"title": "Roads", "mbid": None, "plays": 9, "counted": "listeners"}]
    assert artist_answer(INFO, TRACKS, Answer({}), Answer({"top_albums": {}}), None)["top_albums"] == []
