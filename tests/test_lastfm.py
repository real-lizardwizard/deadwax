"""
Last.fm's answers parsed, and an artist's top songs folded (2.1.41, S2 - notes/lastfm.md): src/lastfm.py artist_info(),
top_tracks(), top_songs(), count(), lastfm_url() and artist_answer().

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

from src.lastfm import (BIO_MAX, CONTENT_BYTES, COUNT_DIGITS, LASTFM_SHAPE, NO_KEY_WHY, SUMMARY_BYTES, SUMMARY_LETTERS,
                        TOP_SONGS, URL_MAX, Answer, Limited, NotKnown, Refused, Unreachable, album_info, artist_answer,
                        artist_info, classify, cleaned, count, lastfm_url, match_key, name_key, no_key_answer,
                        top_songs, top_tracks, tracks_of, without, written_size)
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
    """Every kept row's key begins with LASTFM_SHAPE: a change to what artist_info or top_tracks keep - or to the
    fold, kept folded - must bump it (the SCAN_FORMAT rule)."""
    assert set(top_tracks({"toptracks": {"track": [shaped_track("Elephant")]}})) == {"artist_url", "top_songs"}
    assert set(top_tracks({"toptracks": {"track": [shaped_track("Elephant")]}})["top_songs"][0]) == {
        "title", "playcount", "listeners", "url"}


#? what each LASTFM_SHAPE keeps, as kept_digest() makes it. 2.1.41 kept nothing before it, so its shape is 1. A new
#? shape is added here, never put in place of the one before
KEPT_SHAPES = {
    1: "1aa7a8afb08b1358de968e031b32b2ba6aa36434a24b60a21d5967dc66b728cd",
}

#? SHAPED: titles the fold has to decide, beyond what the recordings hold - so the digest moves with match_key too
FOLD_CASES = ("Let It Happen", "Elephant", "Let It Happen - 2015 Remaster", "Let It Happen (Soulwax Remix)",
              "Lost in Yesterday (feat. Someone Else)", "Lost in Yesterday", "The Less I Know the Better",
              "The Less I Know The Better", "D" + chr(0xE9) + "sire Be Desire Go", "Desire Be Desire Go", "???", "",
              "Let It Happen - Radio Edit", "Dancing with Myself", "Dancing", "Glory Box - Live", "Glory Box",
              "Roads", "Mysterons", "Numb", "Strangers")


def kept_digest() -> str:
    """What src/lastfm.py keeps, digested: getInfo and getTopTracks parsed and folded over every recording, the fold
    over FOLD_CASES, a bio cut by its bytes, and TOP_SONGS and the caps."""
    made = {
        "limits": [TOP_SONGS, BIO_MAX, SUMMARY_LETTERS, CONTENT_BYTES, SUMMARY_BYTES, URL_MAX, COUNT_DIGITS],
        "recorded": {path.stem: (top_tracks if ".top-tracks" in path.stem else artist_info)(answer(path.stem))
                     for path in sorted(ANSWERS.glob("*.json")) if ".top-tracks" in path.stem or ".info" in path.stem},
        "fold": top_songs([shaped_track(name) for name in FOLD_CASES]),
        "bio": artist_info({"artist": {"bio": {"summary": chr(0x1F3B8) * 2000, "content": chr(0x416) * 5000}}}),
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


# ----- the answer ----------------------------------------------------------------------------------------------------

INFO = Answer({"url": "https://www.last.fm/music/Tame+Impala", "listeners": 2345678,
               "bio": {"summary": None, "content": None}})
TRACKS = Answer({"artist_url": "https://www.last.fm/music/Tame+Impala",
                 "top_songs": [{"title": "Elephant", "playcount": 5, "listeners": 2,
                                "url": "https://www.last.fm/music/Tame+Impala/_/Elephant"}]})
REFUSAL = Refused(10, "Invalid API key - You must be granted a valid key by last.fm", 1_764_000_000.0)


def test_an_answer_with_both_parts():
    assert artist_answer(INFO, TRACKS, None) == {
        "enabled": True, "unavailable": False, "why": None, "url": "https://www.last.fm/music/Tame+Impala",
        "listeners": 2345678, "top_songs": TRACKS.body["top_songs"]}


def test_one_part_failing_or_late_leaves_the_other():
    for failed in (Unreachable("HTTP 500"), Limited("error 29"), None):
        got = artist_answer(failed, TRACKS, None)
        assert (got["enabled"], got["unavailable"], got["why"]) == (True, True, None)
        assert got["listeners"] is None and got["top_songs"] == TRACKS.body["top_songs"]
        #? the address from the top tracks' artist, getInfo gone
        assert got["url"] == "https://www.last.fm/music/Tame+Impala"
        got = artist_answer(INFO, failed, None)
        assert got["unavailable"] and got["top_songs"] is None and got["listeners"] == 2345678


def test_an_artist_last_fm_doesnt_know_is_nothing_and_nothing_failed():
    assert artist_answer(NotKnown(), NotKnown(), None) == {
        "enabled": True, "unavailable": False, "why": None, "url": None, "listeners": None, "top_songs": None}
    #? known, but listing nothing
    assert artist_answer(INFO, Answer({"artist_url": None, "top_songs": []}), None)["top_songs"] == []


def test_refused_with_nothing_kept_is_off_and_says_why():
    got = artist_answer(REFUSAL, REFUSAL, REFUSAL)
    assert got == {"enabled": False, "unavailable": True,
                   "why": "Last.fm refused deadwax's API key (error 10: Invalid API key - You must be granted a valid "
                          "key by last.fm) - check LASTFM_API_KEY in Server settings > Connections: it's the API key, "
                          "not the shared secret.",
                   "url": None, "listeners": None, "top_songs": None}
    #? something kept: answered, and still why
    got = artist_answer(INFO, REFUSAL, REFUSAL)
    assert got["enabled"] and got["listeners"] == 2345678 and got["why"].startswith("Last.fm refused")


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
                               "listeners": None, "top_songs": None}
    assert NO_KEY_WHY == ("No Last.fm API key is set - add LASTFM_API_KEY in Server settings > Connections (a free key "
                          "from last.fm/api/account/create).")


def test_a_kept_row_read_back_carefully():
    """A kept row is deadwax's own, but read as carefully as an answer: a bad address or count never passed on."""
    odd = Answer({"url": "http://evil.example/", "listeners": "12", "top_songs": "x"})
    got = artist_answer(odd, Answer({"top_songs": [{"title": ""}, "x", {"title": "Elephant", "url": "http://x/"}]}),
                        None)
    assert got["url"] is None and got["listeners"] == 12
    assert got["top_songs"] == [{"title": "Elephant", "playcount": None, "listeners": None, "url": None}]
