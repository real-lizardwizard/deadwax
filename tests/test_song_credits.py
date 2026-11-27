"""
A song's credits - who played what - from MusicBrainz (credits, slice C1, 27 Nov 2026): src/credits.py (pure), the
client's get_release_credits (kept parsed, in memory and on disk) and the route `GET /deadwax/credits/song/{song_id}`
(src/routes/credits.py), through the whole app with a real MusicBrainzClient and fakes for MusicBrainz and Navidrome.
The suite never calls out.

THE ANSWERS: tests/fixtures/credits/ (its README.md says what each is). Case 1 is REAL - Back in Black's 2003 US
release, fetched on 27 Nov with the lookup's first `inc` (before `release-groups` joined it, so the sample has no
release group: with_group() adds one here, said so where it is used). Cases 2, 3 and 4a and the compilation are MADE,
NOT FETCHED, in MusicBrainz's documented shape and the real answer's structure, each file saying so in its `_made`
field; 4b is Navidrome's album with no release id, made here. Navidrome's getSong and getAlbum are shaped from its
answers as notes/app.md read them in 0.64.2's responses.go: a song's `musicBrainzId` is its recording's id ("" for
everything deadwax filed), `discNumber` and `track` left out when unset, an album's `musicBrainzId` its release id.

What these hold:
  - CASE 1 on the real sample: its ten tracks each placed and shown - lead vocals first, the credited form ("lead
    guitar", "rhythm guitar"), the qualifier dropped ("drums"), writers through the work, production with the
    release's remastering added and its extra engineers not, the recording dates in words, other songs credited;
    what is kept a fifth of what came, with no photography, design, liner notes or `target-credit`.
  - CASE 2: the release's performers "on the album" - a join, guest and solo kept as words, an orchestra and a
    conductor last, the artist's name never the printed one; Music by and Words by; photography never shown.
  - CASE 3: "band", never "song" - the members nothing rules out on the album's date, the release group's (never
    the single out before it), with their instruments from the membership; one who left before or joined after left
    out, at the precision both dates have; a start or end that can't be ordered within the album's year said as
    joined or left; no dates at all said as `dated: false`; a 404 for the band "none", kept.
  - THE COMPILATION: its own date (never its oldest or newest song's, nor the reissue's), and never the band's line-up.
  - CASE 4a "none", 4b "unmatched".
  - THE PAIRING: by recording id, else disc and track only when the disc's track numbers are the release's
    positions - a mismatch (a song more or less, a number twice) is the album's answer, never another track's
    credits; a pregap and data tracks counted as MusicBrainz counts them.
  - THE CLIENT: its own `inc`, RELEASE_FULL_INC untouched; kept parsed in memory and on disk; a kept answer of an
    old shape asked again, from memory and from the disk; a refresh behind an old answer kept parsed too; 30 days.
  - THE ROUTE: a user's (ROUTES), asked as the asker; one lookup per key however many ask, shielded; a kept answer
    while MusicBrainz is down (after a restart); "unavailable" with nothing kept, past its deadline (and kept when
    it comes), with Navidrome away, on a fault in deadwax or as deadwax stops - never a 500; stop() leaves nothing
    under way; a song you may not have a 404; the answer's keys.
"""

import asyncio
import copy
import json
import sqlite3
import sys
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from src import credits as C  # noqa: E402
from src import musicbrainz_cache  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.musicbrainz_endpoint import CREDITS_INC, MusicBrainzClient, RateLimit, ResponseCache  # noqa: E402
from src.api.navidrome_endpoint import navidrome  # noqa: E402
from src.config import Config  # noqa: E402
from src.musicbrainz_cache import SavedAnswers  # noqa: E402
from src.routes import credits as route  # noqa: E402
from tests import test_personal_libraries  # noqa: E402
from tests.test_personal_libraries import NAVIDROME, Navidrome as LibraryNavidrome, run, signed_in, wire  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "credits"

#? the fixture these build on, bound here as the other step-5 suites bind it
on = test_personal_libraries.on


def fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


REAL = fixture("back-in-black-2003-us.json")
CASE2 = fixture("made-case2-album-credits.json")
CASE3 = fixture("made-case3-band-release.json")
CASE3_ARTIST = fixture("made-case3-band-artist.json")
CASE4A = fixture("made-case4a-nothing.json")
COMPILATION = fixture("made-compilation.json")

BIB = REAL["id"]
ACDC = "66c662b6-6e2f-4930-8610-912e24c63ed1"
BAND = CASE3_ARTIST["id"]
BACK_IN_BLACK_SONG = "ef71afb6-5e51-41df-999b-9e7c7306063a"
FETCHED = 1_764_201_600.0
KEYS = {"level", "year", "dated", "others_credited", "performers", "written", "production", "recorded", "source_url"}
PERFORMER = {"id", "name", "did", "joined", "left"}


def with_group(payload: dict, date: str, secondary=()) -> dict:
    """A release answer with its release group as `inc=release-groups` gives it (musicbrainz-server's JSON
    ReleaseGroup serializer: first-release-date and secondary-types always there) - ADDED HERE, not fetched: the real
    sample was fetched before the lookup asked for it. Back in Black's album was first released on 25 July 1980."""
    payload = copy.deepcopy(payload)
    payload["release-group"] = {"id": "00000000-0000-4000-8000-00000000a001", "title": payload.get("title", ""),
                                "primary-type": "Album", "secondary-types": list(secondary),
                                "first-release-date": date, "disambiguation": ""}
    return payload


REAL_GROUPED = with_group(REAL, "1980-07-25")


def kept(payload: dict) -> dict:
    return C.kept(payload, FETCHED)


def track_at(found: dict, disc: int, position: int) -> dict:
    medium = next(m for m in found["media"] if m["position"] == disc)
    return next(t for t in medium["tracks"] if t["position"] == position)


def numbered(count: int) -> tuple[int, ...]:
    """A disc's track numbers in Navidrome, 1 to `count`."""
    return tuple(range(1, count + 1))


def names(rows) -> list[str]:
    return [person["name"] for person in rows]


def rows(answer_rows) -> list[tuple[str, list[str]]]:
    return [(row["job"], names(row["people"])) for row in answer_rows]


def did(performers) -> list[tuple[str, list[str]]]:
    return [(p["name"], p["did"]) for p in performers]


def times(performers) -> dict[str, tuple]:
    """Each performer's joined and left, those with either."""
    return {p["name"]: (p["joined"], p["left"]) for p in performers if p["joined"] or p["left"]}


# ----------------------------------------------------------------- case 1, the real sample

def test_what_is_kept_is_what_is_drawn_and_a_fifth_of_what_came():
    found = kept(REAL)
    assert found["shape"] == C.CREDITS_SHAPE == 2 and found["fetched_at"] == FETCHED and found["id"] == BIB
    assert found["artists"] == [{"id": ACDC, "name": "AC/DC", "type": "Group"}]
    #? the sample has no release group (fetched before the lookup asked for one): no date, and not a compilation
    assert found["first_released"] is None and found["compilation"] is False
    assert kept(REAL_GROUPED)["first_released"] == "1980-07-25"
    [disc] = found["media"]
    assert disc["position"] == 1 and disc["track_count"] == 10
    assert [t["position"] for t in disc["tracks"]] == list(range(1, 11))
    assert [t["recording"] for t in disc["tracks"]] == [t["recording"]["id"] for t in REAL["media"][0]["tracks"]]
    #? a recording's own first release date is never kept: it is a single's, or a compilation's oldest song's
    assert all(set(t) == {"position", "recording", "credits", "written"} for t in disc["tracks"])
    #? the credited form kept beside the attribute
    guitars = [c for c in disc["tracks"][0]["credits"] if c["attributes"] == ["guitar"]]
    assert [(c["name"], c["credited"]) for c in guitars] == [("Angus Young", {"guitar": "lead guitar"}),
                                                            ("Malcolm Young", {"guitar": "rhythm guitar"})]
    #? the release's own: engineers and mastering kept, photography, design, art direction and liner notes never
    assert sorted({c["type"] for c in found["credits"]}) == ["engineer", "mastering"]
    #? the name kept is the artist's - `target-credit`, the name as printed, isn't kept at all
    assert {c["name"] for c in found["credits"]} == {"Benjamin Armbrister", "Jack Nuber", "George Marino"}
    assert "target-credit" not in json.dumps(found) and "Benji" not in json.dumps(found)
    assert len(json.dumps(found)) * 4 < len(json.dumps(REAL))


def test_every_track_of_the_real_sample_is_credited_on_the_song():
    found = kept(REAL_GROUPED)
    album = navidrome_album(BIB, 10)
    for n in range(1, 11):
        where = C.navidrome_place({"discNumber": 1, "track": n, "musicBrainzId": ""}, album)
        track = C.place(found, where)
        assert track is not None and track["recording"] == REAL["media"][0]["tracks"][n - 1]["recording"]["id"]
        said = C.answer(found, track, year=1980)
        assert said["level"] == "song" and set(said) == KEYS
        assert did(said["performers"]) == [
            ("Brian Johnson", ["lead vocals"]),
            ("Phil Rudd", ["drums"]),
            ("Cliff Williams", ["bass guitar"]),
            #? as credited: MusicBrainz's "guitar" for both, with the release's own words for each
            ("Angus Young", ["lead guitar"]),
            ("Malcolm Young", ["rhythm guitar"]),
        ]
        assert all(set(p) == PERFORMER and p["joined"] is None and p["left"] is None for p in said["performers"])
        assert all(C.MBID.match(p["id"]) for p in said["performers"])
        assert rows(said["written"]) == [("Written by", ["Brian Johnson", "Angus Young", "Malcolm Young"])]
        #? producer, engineer, assistants, mix - then the release's remastering, not its extra engineers (the song
        #? names its own engineers)
        assert rows(said["production"]) == [
            ("Producer", ["Robert John “Mutt” Lange"]),
            ("Engineer", ["Tony Platt"]),
            ("Assistant engineer", ["Benjamin Armbrister", "Jack Nuber"]),
            ("Mix", ["Brad Samuelsohn"]),
            ("Remastering", ["George Marino"]),
        ]
        assert said["recorded"] == {"begin": "1980-04", "end": "1980-05", "words": "April to May 1980"}
        assert said["year"] == 1980 and said["dated"] is None
        #? the other nine songs have their performers too
        assert said["others_credited"] is True
        assert said["source_url"] == f"https://musicbrainz.org/release/{BIB}"


def test_a_song_not_placed_on_the_real_sample_gets_the_album_s_own_credits_never_a_track_s():
    said = C.answer(kept(REAL), None, year=1980)
    #? no performer on the release itself: what it lists for itself, production alone, by the artists' own names
    assert said["level"] == "album" and said["performers"] == [] and said["written"] == []
    assert rows(said["production"]) == [("Additional engineer", ["Benjamin Armbrister", "Jack Nuber"]),
                                        ("Remastering", ["George Marino"])]
    #? its songs have credits, and the app can say so
    assert said["others_credited"] is True
    #? the real sample has performers on every song, so the band never stands in
    assert C.band_of(kept(REAL)) is None


def test_others_credited_is_whether_another_song_on_the_release_has_performers():
    only_six = copy.deepcopy(REAL)
    for n, track in enumerate(only_six["media"][0]["tracks"], start=1):
        if n != 6:
            track["recording"]["relations"] = [r for r in track["recording"]["relations"]
                                               if r.get("type") not in C.PERFORMING]
    found = kept(only_six)
    six, one = track_at(found, 1, 6), track_at(found, 1, 1)
    assert C.answer(found, six, year=1980)["others_credited"] is False
    #? song 1 has no performers of its own - its writers and production, and the word that others have some
    said = C.answer(found, one, year=1980)
    assert said["level"] == "song" and said["performers"] == [] and said["others_credited"] is True
    assert C.answer(found, None, year=1980)["others_credited"] is True
    #? performers on the release itself are no other SONG's
    assert C.answer(kept(CASE2), track_at(kept(CASE2), 1, 1), year=1999)["others_credited"] is False
    assert C.empty("unavailable")["others_credited"] is False


def test_an_instrument_is_said_as_credited_else_by_its_name_with_the_bracket_dropped():
    base = {"type": "instrument", "name": "X", "id": None, "begin": None, "end": None}
    shown = C.performers([
        {**base, "attributes": ["guitar", "solo"], "credited": {"guitar": "slide guitar"}},
        {**base, "name": "Y", "attributes": ["drums (drum set)"], "credited": {}},
        #? a vocal's place is its own name's, whatever it is credited as
        {**base, "name": "Z", "type": "vocal", "attributes": ["lead vocals"], "credited": {"lead vocals": "voice"}},
    ])
    assert did(shown) == [("Z", ["voice"]), ("X", ["slide guitar (solo)"]), ("Y", ["drums"])]


# ----------------------------------------------------------------- case 2 (made): credits for the whole album

def test_the_album_s_own_performers_are_shown_on_the_album():
    found = kept(CASE2)
    track = C.place(found, C.Where(None, 1, 2, numbered(3)))
    said = C.answer(found, track, year=1999)
    assert said["level"] == "album"
    assert did(said["performers"]) == [
        #? the artist's name, never "A. Singer" as the sleeve printed it
        ("Ada Singer", ["lead vocals"]),
        #? two credits of one person on one song, joined - in MusicBrainz's order
        ("Ben Player", ["guitar", "background vocals"]),
        ("Cy Drummer", ["drums"]),
        ("Di Keys", ["piano (guest)"]),
        ("Eve Reed", ["saxophone (solo)"]),
        #? an orchestra and a conductor after everyone who played, in MusicBrainz's order
        ("Fay Baton", ["conductor"]),
        ("The Made Strings", ["orchestra"]),
    ]
    assert "A. Singer" not in json.dumps(said)
    #? this song's work separates them: Music by and Words by, its writer on both
    assert rows(said["written"]) == [("Music by", ["Ada Singer", "Lu Notes"]), ("Words by", ["Ada Singer"])]
    assert rows(said["production"]) == [("Producer", ["Gus Knobs"]), ("Executive producer", ["Hal Money"]),
                                        ("Engineer", ["Ivy Desk"]), ("Mix", ["Ivy Desk"]), ("Mastering", ["Jo Lathe"])]
    assert "Kim Lens" not in json.dumps(said), "photography and design are never shown"
    assert said["recorded"] == {"begin": "1999-03", "end": "1999-04", "words": "March to April 1999"}


def test_music_by_and_words_by_only_when_a_work_separates_them():
    found = kept(CASE2)
    assert rows(C.answer(found, track_at(found, 1, 1), year=1999)["written"]) == [
        ("Music by", ["Lu Notes"]), ("Words by", ["Mo Words"])]
    assert rows(C.answer(found, track_at(found, 2, 1), year=1999)["written"]) == [
        ("Written by", ["Ben Player", "Ada Singer"])]
    assert C.answer(found, track_at(found, 1, 3), year=1999)["written"] == []


# ----------------------------------------------------------------- case 3 (made): the band that year

#? case 3's line-up on 2 June 1978, the album's date: lead vocals first, then by who sang, then when they joined
ON_THE_DAY = [
    ("Nan Voice", ["lead vocals"]),
    ("Rae Beat", ["drums", "background vocals"]),
    #? ended, with no end date: nothing rules her out
    ("Uma Gone", ["guitar"]),
    ("Ole Strings", ["guitar"]),
    ("Quin Low", ["bass guitar"]),
    ("Vic Guest", ["saxophone (additional)"]),
    #? no dates at all, nothing known of what he played: counted, with no words
    ("Tam Unknown", []),
]


def test_with_no_credits_the_band_s_members_on_the_album_s_date_stand_in_and_never_on_the_song():
    found = kept(CASE3)
    assert C.band_of(found) == BAND
    #? the release group's date - never the single's (song 1, out in November 1977), nor the 2004 pressing's
    when = C.album_date({"originalReleaseDate": {"year": 1978}, "year": 2004}, found)
    assert when == "1978-06-02"
    members, dated = C.line_up(CASE3_ARTIST, when)
    assert dated is True
    said = C.answer(found, track_at(found, 1, 1), year=1978, band=BAND, members=members, dated=dated)
    #? its own level, which the app heads "The band in 1978" - never "song", which it words "on this song"
    assert said["level"] == "band" and said["level"] != "song"
    assert said["year"] == 1978 and said["recorded"] is None and said["dated"] is True
    assert said["others_credited"] is False
    assert said["source_url"] == f"https://musicbrainz.org/artist/{BAND}"
    assert did(said["performers"]) == ON_THE_DAY
    assert all(set(p) == PERFORMER for p in said["performers"]) and times(said["performers"]) == {}
    #? left in January (Pat), joined the next year (Sol), and the supergroup the band is itself a member of, or a
    #? tribute - none of them. Measured against the single's date instead, Pat would be in and Quin and Vic out
    assert not {"Pat Low", "Sol Later", "The Made Supergroup", "The Made Tribute"} & set(names(said["performers"]))


def test_with_only_the_year_known_a_member_who_joined_or_left_that_year_is_listed_saying_so():
    #? no release group: Navidrome's original year alone, so Pat (left January 1978), Quin (joined February) and
    #? Vic (May to July) can't be ordered against the album - listed, with the year they joined or left
    bare = copy.deepcopy(CASE3)
    del bare["release-group"]
    when = C.album_date({"originalReleaseDate": {"year": 1978}}, kept(bare))
    assert when == "1978"
    members, dated = C.line_up(CASE3_ARTIST, when)
    assert dated is True
    assert names(members) == ["Nan Voice", "Rae Beat", "Pat Low", "Uma Gone", "Ole Strings", "Quin Low", "Vic Guest",
                              "Tam Unknown"]
    assert times(members) == {"Pat Low": (None, 1978), "Quin Low": (1978, None), "Vic Guest": (1978, 1978)}
    #? and Sol, who joined in 1979, never
    assert "Sol Later" not in names(members)


def test_a_time_in_the_band_is_ruled_out_only_at_the_precision_both_dates_have():
    #? Back in Black, 25 July 1980: its singer joined that April; the singer before him died that February
    assert C.membership("1980-04", None, "1980-07-25") == {"joined": None, "left": None}
    assert C.membership("1974", "1980-02-19", "1980-07-25") is None
    #? with the album's year alone, neither can be ordered against it: both listed, saying so
    assert C.membership("1980-04", None, "1980") == {"joined": 1980, "left": None}
    assert C.membership("1974", "1980-02-19", "1980") == {"joined": None, "left": 1980}
    assert C.membership("1974", "1981", "1980") == {"joined": None, "left": None}
    #? the start: at the month both have, the same month can't be ordered; a later month is after
    assert C.membership("1980-07", None, "1980-07-25") == {"joined": 1980, "left": None}
    assert C.membership("1980-08", None, "1980-07-25") is None
    assert C.membership("1980", None, "1980-07-25") == {"joined": 1980, "left": None}
    assert C.membership("1981", None, "1980") is None
    #? the end: on the album's very day is not before it; the day before is
    assert C.membership("1974", "1980-07-25", "1980-07-25") == {"joined": None, "left": 1980}
    assert C.membership("1974", "1980-07-24", "1980-07-25") is None
    assert C.membership("1974", "1980-07", "1980-07-25") == {"joined": None, "left": 1980}
    assert C.membership("1974", "1980-06", "1980-07-25") is None
    #? an unknown start or end rules nothing out
    assert C.membership(None, None, "1980-07-25") == {"joined": None, "left": None}
    assert C.membership(None, "1981", "1980") == {"joined": None, "left": None}
    assert C.membership(None, "1979", "1980") is None
    assert C.order("1980-04", "1980") == 0 and C.order("1980-04", "1980-07-25") == -1
    assert C.order("1981", "1980-07-25") == 1 and C.order("1980-07-25", "1980-07-25") == 0


def test_with_no_member_dated_every_member_is_shown_and_the_answer_says_so():
    undated = copy.deepcopy(CASE3_ARTIST)
    for relation in undated["relations"]:
        relation["begin"] = relation["end"] = None
    members, dated = C.line_up(undated, "1978-06-02")
    assert dated is False
    #? everyone who was ever a member, Pat and Sol among them, and nobody's joined or left
    assert set(names(members)) == {"Nan Voice", "Ole Strings", "Pat Low", "Quin Low", "Rae Beat", "Sol Later",
                                   "Tam Unknown", "Uma Gone", "Vic Guest"}
    assert times(members) == {}
    found = kept(CASE3)
    said = C.answer(found, track_at(found, 1, 1), year=1978, band=BAND, members=members, dated=dated)
    #? the app heads it "The band's members", not "The band in 1978"
    assert said["level"] == "band" and said["dated"] is False
    #? the album's date unknown: nothing can be measured either
    members, dated = C.line_up(CASE3_ARTIST, None)
    assert dated is False and len(members) == 9 and times(members) == {}


def test_a_member_s_two_memberships_and_their_credited_instrument():
    ids = {"Wes Twice": "00000000-0000-4000-8000-0000000000e1", "Xan Once": "00000000-0000-4000-8000-0000000000e2"}

    def member(name, begin, end, attributes, credited=None):
        relation = {"type": "member of band", "direction": "backward", "target-type": "artist",
                    "artist": {"id": ids[name], "name": name},
                    "begin": begin, "end": end, "ended": end is not None, "attributes": attributes}
        if credited:
            relation["attribute-credits"] = credited
        return relation

    band = {"relations": [
        member("Wes Twice", "1975", None, ["guitar"], {"guitar": "lead guitar"}),
        member("Wes Twice", "1980-04", None, ["lead vocals"]),
        member("Xan Once", "1980-04", None, ["bass guitar"]),
    ]}
    members, _ = C.line_up(band, "1980")
    #? one row for Wes - singing first, the guitar as credited - and since one of his memberships plainly covers
    #? 1980, nothing in doubt; Xan's only one can't be ordered
    assert did(members) == [("Wes Twice", ["lead vocals", "lead guitar"]), ("Xan Once", ["bass guitar"])]
    assert times(members) == {"Xan Once": (1980, None)}


def test_a_band_with_everyone_ruled_out_is_none_and_a_credit_anywhere_rules_the_band_out():
    dated_only = copy.deepcopy(CASE3_ARTIST)
    dated_only["relations"] = [r for r in dated_only["relations"] if r.get("begin")]
    members, dated = C.line_up(dated_only, "1960")
    assert members == [] and dated is True
    found = kept(CASE3)
    said = C.answer(found, track_at(found, 1, 1), year=1960, band=BAND, members=members, dated=dated)
    assert said["level"] == "none" and said["dated"] is None
    #? one performer credit on one other song: the album has credits, so its line-up never stands in
    credited = copy.deepcopy(CASE3)
    credited["media"][0]["tracks"][3]["recording"]["relations"] = [CASE2["relations"][0]]
    assert C.band_of(kept(credited)) is None


# ----------------------------------------------------------------- the album's date

def test_the_album_s_date_is_its_release_group_s_never_a_recording_s():
    #? a single out before the album (case 3's song 1, November 1977): the album's date is still June 1978
    single = kept(CASE3)
    assert C.album_date({}, single) == "1978-06-02" and C.album_year({"year": 2004}, single) == 1978
    #? a compilation of songs first out 1976 to 1985, itself first out in 1990, this pressing 2001's: 1990 - not
    #? its oldest song's year, not its newest's, not the pressing's
    hits = kept(COMPILATION)
    assert hits["compilation"] is True and hits["first_released"] == "1990-10-01"
    assert C.album_date({}, hits) == "1990-10-01" and C.album_year({"year": 2001}, hits) == 1990
    assert {t["recording"]["first-release-date"][:4] for t in COMPILATION["media"][0]["tracks"]} == {
        "1976", "1978", "1981", "1985"}


def test_navidrome_s_original_date_counts_where_it_is_more_precise_and_agrees():
    group_year = kept(with_group(REAL, "1980"))
    assert C.album_date({"originalReleaseDate": {"year": 1980, "month": 7, "day": 25}}, group_year) == "1980-07-25"
    grouped = kept(REAL_GROUPED)
    assert C.album_date({"originalReleaseDate": {"year": 1980}}, grouped) == "1980-07-25"
    #? a tag that disagrees with MusicBrainz's release group loses to it
    assert C.album_date({"originalReleaseDate": {"year": 1979, "month": 1, "day": 1}}, grouped) == "1980-07-25"
    assert C.album_date({"originalReleaseDate": {"year": 1980, "month": 8}}, kept(with_group(REAL, "1980-07"))) == (
        "1980-07")
    #? no release group (an answer that lacks it): Navidrome's, as precisely as it gives it
    assert C.album_date({"originalReleaseDate": {"year": 1980, "month": 7}}, kept(REAL)) == "1980-07"
    assert C.album_date({"originalReleaseDate": {}}, None) is None


def test_the_album_s_year_is_its_original_year():
    found = kept(REAL)
    #? Navidrome's originalReleaseDate (the originaldate tag: original_year), never the pressing's 2003
    assert C.album_year({"originalReleaseDate": {"year": 1980}, "year": 2003}, found) == 1980
    #? no original date in Navidrome (an MP4 can't hold the tag): the release group's
    assert C.album_year({"year": 2003}, kept(REAL_GROUPED)) == 1980
    #? neither: the date tag's, for the answer's year alone - a line-up is never measured against it
    assert C.album_year({"year": 2003}, found) == 2003 and C.album_date({"year": 2003}, found) is None
    assert C.album_year({"year": 2003}, None) == 2003
    assert C.album_year({}, None) is None


def test_a_compilation_never_has_the_band_s_line_up():
    hits = kept(COMPILATION)
    assert hits["artists"][0]["type"] == "Group" and C.band_of(hits) is None
    #? the same release as an album is the band's
    album = copy.deepcopy(COMPILATION)
    album["release-group"]["secondary-types"] = []
    assert C.band_of(kept(album)) == BAND


# ----------------------------------------------------------------- case 4a and the answers with nothing

def test_nothing_at_all_is_none():
    found = kept(CASE4A)
    assert C.band_of(found) is None, "one Person: no band"
    said = C.answer(found, C.place(found, C.Where(None, 1, 1, numbered(2))), year=2011)
    assert said == {**C.empty("none", 2011), "source_url": f"https://musicbrainz.org/release/{CASE4A['id']}"}


def test_every_answer_has_the_same_keys():
    assert set(C.empty("unmatched")) == set(C.empty("unavailable")) == KEYS
    assert C.empty("none")["dated"] is None and C.empty("none")["others_credited"] is False
    assert set(C.LEVELS) == {"song", "album", "band", "none", "unmatched", "unavailable"}


# ----------------------------------------------------------------- the pairing

def test_a_song_is_placed_by_its_recording_id_first():
    found = kept(REAL)
    #? by recording, wherever Navidrome says it sits - and the disc's numbers don't matter then
    assert C.place(found, C.Where(BACK_IN_BLACK_SONG, None, None, ()))["position"] == 6
    #? an id the release doesn't carry is no pairing - never a fall back to the position
    assert C.place(found, C.Where("00000000-0000-4000-8000-000000000000", 1, 6, numbered(10))) is None


def test_by_disc_and_track_only_when_the_disc_s_track_numbers_are_the_release_s():
    found = kept(REAL)
    assert C.place(found, C.Where(None, 1, 6, numbered(10)))["recording"] == BACK_IN_BLACK_SONG
    #? a folder with nine or eleven songs on the disc is not this release as it is: no pairing
    assert C.place(found, C.Where(None, 1, 6, numbered(9))) is None
    assert C.place(found, C.Where(None, 1, 6, numbered(11))) is None
    #? ten songs, but two numbered 6 (and no 7), one numbered past the end, or one with no number: no pairing
    assert C.place(found, C.Where(None, 1, 6, (1, 2, 3, 4, 5, 6, 6, 8, 9, 10))) is None
    assert C.place(found, C.Where(None, 1, 6, (1, 2, 3, 4, 5, 6, 7, 8, 9, 11))) is None
    assert C.place(found, C.Where(None, 1, 6, (0, 1, 2, 3, 4, 5, 6, 7, 8, 9))) is None
    #? no such disc, no track number, a track past the end
    assert C.place(found, C.Where(None, 2, 1, numbered(10))) is None
    assert C.place(found, C.Where(None, 1, None, numbered(10))) is None
    assert C.place(found, C.Where(None, 1, 11, numbered(10))) is None
    #? no disc number: the one disc of a one-disc release - never a guess between two
    assert C.place(found, C.Where(None, None, 6, numbered(10)))["recording"] == BACK_IN_BLACK_SONG
    two = kept(CASE2)
    assert C.place(two, C.Where(None, None, 1, numbered(3))) is None
    assert C.place(two, C.Where(None, 2, 1, numbered(2)))["recording"] == "e2000001-0000-4000-8000-000000000001"
    assert C.place(two, C.Where(None, 2, 1, numbered(3))) is None
    #? a disc MusicBrainz didn't list whole (a huge box set's) is never paired by position
    short = kept(REAL)
    short["media"][0]["track_count"] = 12
    assert C.place(short, C.Where(None, 1, 6, numbered(10))) is None


def test_a_pregap_and_data_tracks_are_neither_listed_nor_counted_with_the_tracks():
    """MusicBrainz keeps them apart: a medium's `pregap` (its track at position 0) and `data-tracks`, both outside
    `tracks` AND `track-count` (musicbrainz-server's Data/Medium.pm counts cdtoc_track_count as the tracks at a
    position above 0 that aren't data; the JSON Medium serializer lists cdtoc_tracks as `tracks`). So an enhanced CD
    pairs like any other, and a disc listed short is still refused, a data track or not."""
    enhanced = copy.deepcopy(REAL)
    medium = enhanced["media"][0]
    hidden = copy.deepcopy(medium["tracks"][0])
    hidden.update(position=0, number="0")
    data = copy.deepcopy(medium["tracks"][9])
    data.update(position=11, number="11")
    medium.update(pregap=hidden, **{"data-tracks": [data]})
    found = kept(enhanced)
    assert [t["position"] for t in found["media"][0]["tracks"]] == list(range(1, 11))
    assert C.place(found, C.Where(None, 1, 6, numbered(10)))["recording"] == BACK_IN_BLACK_SONG
    listed_short = copy.deepcopy(enhanced)
    listed_short["media"][0]["tracks"] = listed_short["media"][0]["tracks"][:9]
    assert C.place(kept(listed_short), C.Where(None, 1, 6, numbered(9))) is None


def test_navidrome_s_song_and_album_say_where_the_song_sits():
    album = navidrome_album(BIB, 10)
    assert C.navidrome_place(album["song"][5], album) == C.Where(None, 1, 6, numbered(10))
    #? a recording id from the file's tag, in any case; discNumber and track left out when unset; a disc's numbers
    #? in order, 0 for a song with none
    tagged = {"discNumber": 2, "track": "3", "musicBrainzId": BACK_IN_BLACK_SONG.upper()}
    album = {"song": [{"discNumber": 2, "track": 3}, {"discNumber": 2, "track": "1"}, {"discNumber": 2},
                      {"discNumber": 1, "track": 1}, {}]}
    assert C.navidrome_place(tagged, album) == C.Where(BACK_IN_BLACK_SONG, 2, 3, (0, 1, 3))
    assert C.navidrome_place({}, album) == C.Where(None, None, None, (0,))
    assert C.release_of({"musicBrainzId": BIB.upper()}) == BIB
    assert C.release_of({"musicBrainzId": "../../artist/x"}) is None and C.release_of({"musicBrainzId": ""}) is None


def test_a_number_is_a_positive_whole_number_and_never_a_fault():
    assert C._number(3) == 3 and C._number("12") == 12 and C._number(" 7 ") == 7
    assert C._number(0) is None and C._number("0") is None and C._number(True) is None
    #? "²" is a digit (isdigit) that int() can't read: isdecimal, so it is no number rather than a ValueError
    assert C._number("²") is None and C._number("3²") is None and C._number("-1") is None
    assert C._number(None) is None and C._number(2.0) is None


def test_recording_dates_in_words():
    assert C.recorded_words("1980-04", "1980-05") == "April to May 1980"
    assert C.recorded_words("1979-12", "1980-01") == "December 1979 to January 1980"
    assert C.recorded_words("1980-04-12", "1980-04-12") == "12 April 1980"
    assert C.recorded_words("1980-04-12", None) == "12 April 1980"
    assert C.recorded_words("1980", "1980-05") == "1980"
    assert C.recorded_words(None, None) is None


# ----------------------------------------------------------------- the client

def test_the_credits_have_their_own_lookup_and_release_full_inc_is_untouched():
    assert MusicBrainzClient.CREDITS_INC == CREDITS_INC == (
        "recordings+artist-credits+artist-rels+recording-level-rels+work-rels+work-level-rels+release-groups")
    #? fetched for every pressing looked at - it must never carry the relations
    assert MusicBrainzClient.RELEASE_FULL_INC == "media+recordings+labels+artist-credits"
    assert not any(part.endswith("-rels") for part in MusicBrainzClient.RELEASE_FULL_INC.split("+"))
    #? credits keep a month, as every lookup on disk does
    assert musicbrainz_cache.fresh_for({"inc": CREDITS_INC, "fmt": "json"}) == 30 * 24 * 3600


class Answer:
    def __init__(self, payload=None, status_code=200):
        self.payload = payload if payload is not None else {}
        self.status_code = status_code
        self.text = "fake"

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPStatusError("refused", request=None, response=self)  # type: ignore[arg-type]

    def json(self):
        return self.payload


class MusicBrainz:
    """MusicBrainz's lookups by endpoint, every request kept - `down` a 403 (asked once, no retries), `delay` slow,
    and every request cancelled mid-way counted."""

    def __init__(self, answers=None):
        self.answers = answers if answers is not None else {
            f"release/{BIB}": REAL_GROUPED, f"release/{CASE2['id']}": CASE2, f"release/{CASE3['id']}": CASE3,
            f"artist/{BAND}": CASE3_ARTIST, f"release/{CASE4A['id']}": CASE4A,
            f"release/{COMPILATION['id']}": COMPILATION}
        self.calls: list[tuple[str, dict]] = []
        self.down = False
        self.delay = 0.0
        self.cancelled = 0

    async def get(self, endpoint, params=None):
        self.calls.append((endpoint, dict(params or {})))
        if self.delay:
            try:
                await asyncio.sleep(self.delay)
            except asyncio.CancelledError:
                self.cancelled += 1
                raise
        if self.down:
            return Answer(status_code=403)
        found = self.answers.get(endpoint)
        return Answer(copy.deepcopy(found)) if found else Answer({"error": "Not Found"}, status_code=404)


def connected(fake: MusicBrainz) -> MusicBrainzClient:
    client = MusicBrainzClient()

    async def get_client():
        return fake

    client.get_client = get_client  # type: ignore[method-assign]
    client.get_refresh_client = get_client  # type: ignore[method-assign]
    return client


@pytest.fixture
def fresh(monkeypatch):
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16))
    monkeypatch.setattr(MusicBrainzClient, "rate_limit", RateLimit())
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "james@example.com")
    monkeypatch.setattr(route, "_no_artist", {})


def test_the_lookup_asks_its_own_inc_and_is_kept_parsed(fresh):
    fake = MusicBrainz()
    client = connected(fake)
    first = run(client.get_release_credits(BIB))
    assert fake.calls == [(f"release/{BIB}", {"inc": CREDITS_INC, "fmt": "json"})]
    assert C.is_current(first) and first["media"][0]["tracks"][5]["recording"] == BACK_IN_BLACK_SONG
    #? kept as parsed: the second answer is from memory, and is the parsed one
    assert run(client.get_release_credits(BIB)) == first and len(fake.calls) == 1
    #? the ordinary release lookup is another question, asked as it always was
    run(client.get_release(BIB))
    assert fake.calls[-1] == (f"release/{BIB}", {"inc": "media+recordings+labels+artist-credits", "fmt": "json"})


def test_a_kept_answer_of_an_old_shape_is_asked_for_again(fresh, monkeypatch):
    fake = MusicBrainz()
    client = connected(fake)
    run(client.get_release_credits(BIB))
    monkeypatch.setattr(C, "CREDITS_SHAPE", C.CREDITS_SHAPE + 1)
    again = run(client.get_release_credits(BIB))
    assert len(fake.calls) == 2 and again["shape"] == C.CREDITS_SHAPE


def test_a_kept_answer_of_an_old_shape_on_disk_is_asked_for_again_after_a_restart(fresh, monkeypatch, tmp_path):
    """The disk's own check (_saved_answer): an answer of shape 1 saved before an upgrade is never answered - the
    lookup asks MusicBrainz afresh, and what it keeps then is today's shape."""
    saved = SavedAnswers(str(tmp_path / "musicbrainz-cache.db"), max_bytes=8 << 20)
    params = {"inc": CREDITS_INC, "fmt": "json"}
    old = {**kept(REAL_GROUPED), "shape": C.CREDITS_SHAPE - 1}
    #? saved just now: fresh by its date, so only its shape says no
    saved.put(ResponseCache.disk_key(f"release/{BIB}", params), old)
    run(saved.flush())
    #? a fresh memory over that file, as after a restart
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16, disk=saved))
    fake = MusicBrainz()
    found = run(connected(fake).get_release_credits(BIB))
    assert fake.calls == [(f"release/{BIB}", params)]
    assert C.is_current(found) and found["shape"] == C.CREDITS_SHAPE
    run(saved.close())


def test_a_refresh_behind_an_old_answer_is_kept_parsed_too(fresh):
    fake = MusicBrainz()
    client = connected(fake)
    refreshed = run(client.request_with_retries(f"release/{BIB}", {"inc": CREDITS_INC, "fmt": "json"},
                                                refreshing=True))
    assert C.is_current(refreshed)
    assert C.is_current(MusicBrainzClient.cache.get(f"release/{BIB}", {"inc": CREDITS_INC, "fmt": "json"}))


# ----------------------------------------------------------------- the route, logins off

def navidrome_album(release: str, count: int, *, album_id: str = "al-1", disc_count=None, year=1980) -> dict:
    """Navidrome's getAlbum as 0.64.2 answers it: the release id, the original date, and its songs."""
    songs = [{"id": f"so-{n}", "albumId": album_id, "discNumber": 1, "track": n, "musicBrainzId": "",
              "title": f"Song {n}"} for n in range(1, (disc_count or count) + 1)]
    return {"id": album_id, "name": "Back in Black", "musicBrainzId": release, "year": 2003,
            "originalReleaseDate": {"year": year} if year else {}, "song": songs}


class Library:
    """Navidrome's getSong and getAlbum - songs by id, albums by id - every call kept."""

    def __init__(self):
        self.albums: dict[str, dict] = {}
        self.calls: list[tuple[str, dict]] = []
        self.down = False

    def add(self, album: dict) -> None:
        self.albums[album["id"]] = album

    def handle(self, request: httpx.Request) -> httpx.Response:
        q = {key: values[0] for key, values in parse_qs(urlparse(str(request.url)).query).items()}
        endpoint = request.url.path.rsplit("/", 1)[-1]
        self.calls.append((endpoint, {k: v for k, v in q.items() if k not in ("u", "t", "s", "v", "c", "f")}))
        if self.down:
            raise httpx.ConnectError("connection refused")
        if endpoint == "getSong":
            song = next((s for a in self.albums.values() for s in a["song"] if s["id"] == q.get("id")), None)
            return httpx.Response(200, json=ok(song=song) if song else failed(70, "Song not found"))
        if endpoint == "getAlbum":
            album = self.albums.get(q.get("id", ""))
            return httpx.Response(200, json=ok(album=album) if album else failed(70, "Album not found"))
        return httpx.Response(200, json=failed(0, f"not faked: {endpoint}"))


def ok(**body) -> dict:
    return {"subsonic-response": {"status": "ok", "version": "1.16.1", "type": "navidrome", "serverVersion": "0.64.2",
                                  "openSubsonic": True, **body}}


def failed(code: int, message: str) -> dict:
    return {"subsonic-response": {"status": "failed", "version": "1.16.1", "error": {"code": code, "message": message}}}


@pytest.fixture
def env(fresh, monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
    mb = MusicBrainz()
    library = Library()
    library.add(navidrome_album(BIB, 10))
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(library.handle), base_url="http://navidrome:4533/rest")
    app = start()  # no `with`: no lifespan, nothing connects
    app.state.musicbrainz_client = connected(mb)
    yield SimpleNamespace(app=app, client=TestClient(app), mb=mb, library=library, tmp=tmp_path,
                          request=SimpleNamespace(app=app, state=SimpleNamespace()))
    run(navidrome.close_client())


def credits_of(env, song_id: str = "so-6") -> dict:
    answer = env.client.get(f"/deadwax/credits/song/{song_id}")
    assert answer.status_code == 200, answer.text
    return answer.json()


def answerable_copy(said: dict) -> dict:
    return json.loads(json.dumps(said))


def test_the_route_answers_a_song_s_credits_in_its_shape(env):
    said = credits_of(env)
    assert set(said) == KEYS
    assert said["level"] == "song" and said["year"] == 1980 and said["dated"] is None
    assert said["others_credited"] is True
    assert [set(p) for p in said["performers"]] == [PERFORMER] * 5
    assert [set(row) for row in said["written"] + said["production"]] == [{"job", "people"}] * 6
    assert all(set(person) == {"id", "name"} for row in said["production"] for person in row["people"])
    assert said["recorded"] == {"begin": "1980-04", "end": "1980-05", "words": "April to May 1980"}
    assert said["source_url"] == f"https://musicbrainz.org/release/{BIB}"
    found = kept(REAL_GROUPED)
    assert said == answerable_copy(C.answer(found, track_at(found, 1, 6), year=1980))
    #? Navidrome asked for the song, then its album, by id alone; MusicBrainz once, with the credits' own inc
    assert env.library.calls == [("getSong", {"id": "so-6"}), ("getAlbum", {"id": "al-1"})]
    assert env.mb.calls == [(f"release/{BIB}", {"inc": CREDITS_INC, "fmt": "json"})]


def test_a_folder_whose_disc_differs_is_never_paired_by_position(env):
    #? nine songs on the disc in Navidrome against the release's ten: the album's own answer, never track 6's
    env.library.add(navidrome_album(BIB, 9))
    said = credits_of(env)
    assert said["level"] == "album" and said["performers"] == [] and said["written"] == []
    assert "Tony Platt" not in json.dumps(said) and said["others_credited"] is True
    #? ten songs, two of them numbered 5: the same
    doubled = navidrome_album(BIB, 10)
    doubled["song"][5]["track"] = 5
    env.library.add(doubled)
    assert credits_of(env)["level"] == "album"


def test_a_file_s_recording_id_places_it_whatever_the_count(env):
    album = navidrome_album(BIB, 9)
    album["song"][0]["musicBrainzId"] = BACK_IN_BLACK_SONG
    env.library.add(album)
    said = credits_of(env, "so-1")
    assert said["level"] == "song" and said["written"][0]["people"][0]["name"] == "Brian Johnson"


def test_an_album_with_no_release_id_is_unmatched_and_musicbrainz_is_not_asked(env):
    env.library.add(navidrome_album("", 10))
    assert credits_of(env) == C.empty("unmatched", 1980)
    env.library.add(navidrome_album("not-an-id/../../x", 10))
    assert credits_of(env)["level"] == "unmatched"
    assert env.mb.calls == []


def test_a_release_musicbrainz_has_nothing_at_is_unmatched(env):
    env.library.add(navidrome_album("00000000-0000-4000-8000-0000000000ff", 10))
    assert credits_of(env)["level"] == "unmatched"


def test_the_made_cases_through_the_route(env):
    env.library.add(navidrome_album(CASE2["id"], 3, album_id="al-1", year=1999))
    said = credits_of(env, "so-2")
    assert said["level"] == "album" and names(said["performers"])[:2] == ["Ada Singer", "Ben Player"]

    #? Navidrome with only the original year: the release group's day is what the line-up is measured against
    env.library.add(navidrome_album(CASE3["id"], 4, year=1978))
    said = credits_of(env, "so-1")
    assert said["level"] == "band" and said["year"] == 1978 and said["dated"] is True
    assert did(said["performers"]) == ON_THE_DAY
    #? the band's members come from the artist lookup the artist page already makes (ARTIST_INC)
    assert env.mb.calls[-1] == (f"artist/{BAND}", {"inc": MusicBrainzClient.ARTIST_INC, "fmt": "json"})

    env.library.add(navidrome_album(CASE4A["id"], 2, year=2011))
    assert credits_of(env, "so-1") == {**C.empty("none", 2011),
                                       "source_url": f"https://musicbrainz.org/release/{CASE4A['id']}"}


def test_a_compilation_through_the_route_is_its_own_year_and_never_the_band(env):
    #? an MP4 reissue: no original date in Navidrome, the pressing's 2001 as its year
    album = navidrome_album(COMPILATION["id"], 4, year=None)
    album["year"] = 2001
    env.library.add(album)
    said = credits_of(env, "so-1")
    assert said["level"] == "none" and said["year"] == 1990
    assert not [endpoint for endpoint, _ in env.mb.calls if endpoint.startswith("artist/")]


def test_the_band_s_members_unaskable_is_unavailable_not_none(env):
    """No credits on the release, and MusicBrainz away for the band's lookup: whether a line-up would answer is
    unknown - "unavailable", never "none"."""
    env.library.add(navidrome_album(CASE3["id"], 4, year=1978))
    asking = env.mb.get

    async def artist_down(endpoint, params=None):
        if endpoint.startswith("artist/"):
            env.mb.calls.append((endpoint, dict(params or {})))
            return Answer(status_code=403)
        return await asking(endpoint, params)

    env.mb.get = artist_down
    assert credits_of(env, "so-1") == C.empty("unavailable", 1978)


def test_a_band_musicbrainz_has_nothing_at_is_none_and_kept(env, monkeypatch):
    """A 404 for the band's artist is MusicBrainz's answer, not an outage: "none" - and kept, so the next ask doesn't
    ask again (the client keeps successes only)."""
    env.library.add(navidrome_album(CASE3["id"], 4, year=1978))
    del env.mb.answers[f"artist/{BAND}"]
    none = {**C.empty("none", 1978), "source_url": f"https://musicbrainz.org/release/{CASE3['id']}"}
    assert credits_of(env, "so-1") == none
    assert credits_of(env, "so-2") == none
    assert [endpoint for endpoint, _ in env.mb.calls].count(f"artist/{BAND}") == 1
    #? and only for as long as it is kept
    monkeypatch.setattr(route, "NO_ARTIST_KEPT_S", 0.0)
    assert credits_of(env, "so-3") == none
    assert [endpoint for endpoint, _ in env.mb.calls].count(f"artist/{BAND}") == 2


def test_musicbrainz_down_with_nothing_kept_is_unavailable_never_an_error(env):
    env.mb.down = True
    assert credits_of(env) == C.empty("unavailable", 1980)


def test_a_fault_in_deadwax_is_unavailable_never_a_500(env):
    async def broken(release):
        raise RuntimeError("a fault in deadwax")

    env.app.state.musicbrainz_client.get_release_credits = broken
    assert credits_of(env) == C.empty("unavailable", 1980)


def test_navidrome_away_is_unavailable_and_a_song_you_may_not_have_is_a_404(env):
    assert env.client.get("/deadwax/credits/song/so-404").status_code == 404
    assert env.mb.calls == []
    env.library.down = True
    assert credits_of(env) == C.empty("unavailable")
    #? an id far past any of Navidrome's is refused before anything is asked
    asked = len(env.library.calls)
    assert env.client.get("/deadwax/credits/song/" + "x" * 300).status_code == 422
    assert len(env.library.calls) == asked


def test_a_kept_answer_is_used_while_musicbrainz_is_down_after_a_restart(env, monkeypatch):
    saved = SavedAnswers(str(env.tmp / "musicbrainz-cache.db"), max_bytes=8 << 20)
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16, disk=saved))
    first = credits_of(env)
    run(saved.flush())
    #? what is on disk is the parsed answer - under 1.5 KB compressed, where MusicBrainz's whole answer is 9.3
    with sqlite3.connect(saved.path()) as connection:
        [(body,)] = connection.execute("SELECT body FROM answers").fetchall()
    assert C.is_current(musicbrainz_cache.unpack(body)) and len(body) < 3_000

    #? a restart: a new memory over the same file, and MusicBrainz down
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16, disk=saved))
    env.mb.down = True
    asked = len(env.mb.calls)
    assert credits_of(env) == first and first["level"] == "song"
    assert len(env.mb.calls) == asked, "answered from the disk, nothing asked"
    run(saved.close())


def test_past_the_deadline_it_is_unavailable_and_kept_when_it_comes(env, monkeypatch):
    monkeypatch.setattr(route, "CREDITS_DEADLINE_S", 0.05)
    env.mb.delay = 0.3

    async def go():
        late = await route.song_credits(env.request, "so-6")
        while route._running or route._asking:
            await asyncio.sleep(0.02)
        again = await route.song_credits(env.request, "so-6")
        return late, again

    late, again = run(go())
    assert late == C.empty("unavailable", 1980)
    #? the lookup went on behind the answer, and the next ask had it, MusicBrainz asked once in all
    assert again["level"] == "song" and len(env.mb.calls) == 1


def test_however_many_ask_at_once_musicbrainz_is_asked_once(env):
    env.mb.delay = 0.05
    band_album = navidrome_album(CASE3["id"], 4, album_id="al-3", year=1978)
    for song in band_album["song"]:
        song["id"] = f"band-{song['id']}"
    env.library.add(band_album)

    async def go():
        songs = ["so-6"] * 5 + ["band-so-1", "band-so-2", "band-so-3", "band-so-4"]
        return await asyncio.gather(*(route.song_credits(env.request, song) for song in songs))

    said = run(go())
    assert [answer["level"] for answer in said] == ["song"] * 5 + ["band"] * 4
    assert all(answer == said[0] for answer in said[:5]) and all(answer == said[5] for answer in said[5:])
    #? one lookup per key - Back in Black's release, the band's release and the band's artist - each once
    assert sorted(endpoint for endpoint, _ in env.mb.calls) == sorted(
        [f"release/{BIB}", f"release/{CASE3['id']}", f"artist/{BAND}"])
    assert route._asking == {} and route._running == set()


def test_one_ask_that_stops_waiting_never_cancels_the_lookup_the_others_await():
    asked = []

    async def ask():
        asked.append(1)
        await asyncio.sleep(0.05)
        return {"kept": True}

    async def go():
        first = asyncio.create_task(route._shared("release:x", ask))
        second = asyncio.create_task(route._shared("release:x", ask))
        await asyncio.sleep(0.01)
        first.cancel()
        return await second, first

    answer, first = run(go())
    assert answer == {"kept": True} and first.cancelled() and asked == [1]
    assert route._asking == {}


def test_deadwax_stopping_mid_lookup_answers_unavailable_and_leaves_nothing_under_way(env):
    """stop(), as deadwax shuts down: every lookup under way cancelled - each ask's own and the MusicBrainz one they
    share - and an ask still waiting answered "unavailable" at once, never an error."""
    env.mb.delay = 5.0

    async def go():
        asking = asyncio.create_task(route.song_credits(env.request, "so-6"))
        while not route._asking:
            await asyncio.sleep(0.01)
        await route.stop()
        left = (dict(route._asking), set(route._running))
        return await asyncio.wait_for(asking, 1.0), left

    said, (asking, running) = run(go())
    assert said == C.empty("unavailable", 1980)
    assert asking == {} and running == set()
    assert env.mb.cancelled == 1


# ----------------------------------------------------------------- the route, logins on: a user's, as the asker

class AsYou(LibraryNavidrome):
    """Step 5's Navidrome - token auth checked for real, every call kept with who made it - holding Back in Black's
    album, with getSong answered too."""

    def __init__(self):
        super().__init__()
        self.listing = navidrome_album(BIB, 10)
        self.albums[self.listing["id"]] = self.listing

    def handle(self, request: httpx.Request) -> httpx.Response:
        answered = super().handle(request)
        said = answered.json()["subsonic-response"]
        if request.url.path.endswith("/getSong") and said.get("error", {}).get("code") == 0:
            song = next((s for s in self.listing["song"] if s["id"] == request.url.params.get("id")), None)
            return httpx.Response(200, json=ok(song=song) if song else failed(70, "Song not found"))
        return answered


def test_logins_on_it_is_a_user_s_route_asked_as_the_asker(on, monkeypatch):
    fake = AsYou()
    wire(fake)
    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(fake.handle), base_url=f"{NAVIDROME}/rest")
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16))
    monkeypatch.setattr(MusicBrainzClient, "rate_limit", RateLimit())
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "james@example.com")
    mb = MusicBrainz()
    on.app.state.musicbrainz_client = connected(mb)
    path = "/deadwax/credits/song/so-6"
    try:
        assert TestClient(on.app).get(path).status_code == 401
        assert mb.calls == [] and not [c for c in fake.calls if c[1] in ("getSong", "getAlbum")]

        ethan = signed_in(on, "ethan")
        said = ethan.get(path)
        assert said.status_code == 200 and said.json()["level"] == "song"
        #? as ethan - never the shared account
        assert [(user, endpoint) for user, endpoint, _ in fake.calls if endpoint in ("getSong", "getAlbum")] == [
            ("ethan", "getSong"), ("ethan", "getAlbum")]
    finally:
        run(navidrome.close_client())
