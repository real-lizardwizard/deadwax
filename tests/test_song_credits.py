"""
A song's credits - who played what - from MusicBrainz (credits, slice C1, 27 Nov 2026): src/credits.py (pure), the
client's get_release_credits (kept parsed, in memory and on disk) and the route `GET /deadwax/credits/song/{song_id}`
(src/routes/credits.py), through the whole app with a real MusicBrainzClient and fakes for MusicBrainz and Navidrome.
The suite never calls out.

THE ANSWERS: tests/fixtures/credits/ (its README.md says what each is). Case 1 is REAL - Back in Black's 2003 US
release, fetched on 27 Nov with the lookup's own `inc`. Cases 2, 3 and 4a are MADE, NOT FETCHED, in MusicBrainz's
documented shape and the real answer's structure, each file saying so in its `_made` field; 4b is Navidrome's album
with no release id, made here. Navidrome's getSong and getAlbum are shaped from its answers as notes/app.md read them
in 0.64.2's responses.go: a song's `musicBrainzId` is its recording's id ("" for everything deadwax filed),
`discNumber` and `track` left out when unset, an album's `musicBrainzId` its release id.

What these hold:
  - CASE 1 on the real sample: its ten tracks each placed and shown - lead vocals first, the qualifier dropped
    ("drums"), writers through the work, production with the release's remastering added and its extra engineers
    not, the recording dates in words; what is kept a fifth of what came, with no photography, design, liner notes
    or `target-credit`.
  - CASE 2: the release's performers "on the album" - a join, guest and solo kept as words, an orchestra and a
    conductor last, the artist's name never the printed one; Music by and Words by; photography never shown.
  - CASE 3: "band", never "song" - the members whose time surely covers the album's date, with their instruments
    from the membership; a member who left, joined later, has no dates or no end date left out.
  - CASE 4a "none", 4b "unmatched".
  - THE PAIRING: by recording id, else disc and track only when the disc's track counts agree - a mismatch is the
    album's answer, never another track's credits.
  - THE CLIENT: its own `inc`, RELEASE_FULL_INC untouched; kept parsed in memory and on disk; a kept answer of an
    old shape asked again; a refresh behind an old answer kept parsed too; 30 days fresh.
  - THE ROUTE: a user's (ROUTES), asked as the asker; a kept answer while MusicBrainz is down (after a restart);
    "unavailable" with nothing kept, past its deadline (and kept when it comes), or with Navidrome away - never a
    500; a song you may not have a 404; the answer's keys.
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

BIB = REAL["id"]
ACDC = "66c662b6-6e2f-4930-8610-912e24c63ed1"
BACK_IN_BLACK_SONG = "ef71afb6-5e51-41df-999b-9e7c7306063a"
FETCHED = 1_764_201_600.0
KEYS = {"level", "year", "performers", "written", "production", "recorded", "source_url"}


def kept(payload: dict) -> dict:
    return C.kept(payload, FETCHED)


def track_at(found: dict, disc: int, position: int) -> dict:
    medium = next(m for m in found["media"] if m["position"] == disc)
    return next(t for t in medium["tracks"] if t["position"] == position)


def names(rows) -> list[str]:
    return [person["name"] for person in rows]


def rows(answer_rows) -> list[tuple[str, list[str]]]:
    return [(row["job"], names(row["people"])) for row in answer_rows]


# ----------------------------------------------------------------- case 1, the real sample

def test_what_is_kept_is_what_is_drawn_and_a_fifth_of_what_came():
    found = kept(REAL)
    assert found["shape"] == C.CREDITS_SHAPE and found["fetched_at"] == FETCHED and found["id"] == BIB
    assert found["artists"] == [{"id": ACDC, "name": "AC/DC", "type": "Group"}]
    [disc] = found["media"]
    assert disc["position"] == 1 and disc["track_count"] == 10
    assert [t["position"] for t in disc["tracks"]] == list(range(1, 11))
    assert [t["recording"] for t in disc["tracks"]] == [t["recording"]["id"] for t in REAL["media"][0]["tracks"]]
    assert all(t["first_released"] == "1980-07-25" for t in disc["tracks"])
    #? the release's own: engineers and mastering kept, photography, design, art direction and liner notes never
    assert sorted({c["type"] for c in found["credits"]}) == ["engineer", "mastering"]
    #? the name kept is the artist's - `target-credit`, the name as printed, isn't kept at all
    assert {c["name"] for c in found["credits"]} == {"Benjamin Armbrister", "Jack Nuber", "George Marino"}
    assert "target-credit" not in json.dumps(found) and "Benji" not in json.dumps(found)
    assert len(json.dumps(found)) * 4 < len(json.dumps(REAL))


def test_every_track_of_the_real_sample_is_credited_on_the_song():
    found = kept(REAL)
    album = navidrome_album(BIB, 10)
    for n in range(1, 11):
        where = C.navidrome_place({"discNumber": 1, "track": n, "musicBrainzId": ""}, album)
        track = C.place(found, where)
        assert track is not None and track["recording"] == REAL["media"][0]["tracks"][n - 1]["recording"]["id"]
        said = C.answer(found, track, year=1980)
        assert said["level"] == "song" and set(said) == KEYS
        assert [(p["name"], p["did"]) for p in said["performers"]] == [
            ("Brian Johnson", ["lead vocals"]),
            ("Phil Rudd", ["drums"]),
            ("Cliff Williams", ["bass guitar"]),
            ("Angus Young", ["guitar"]),
            ("Malcolm Young", ["guitar"]),
        ]
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
        assert said["year"] == 1980
        assert said["source_url"] == f"https://musicbrainz.org/release/{BIB}"


def test_a_song_not_placed_on_the_real_sample_gets_the_album_s_own_credits_never_a_track_s():
    said = C.answer(kept(REAL), None, year=1980)
    #? no performer on the release itself: what it lists for itself, production alone, by the artists' own names
    assert said["level"] == "album" and said["performers"] == [] and said["written"] == []
    assert rows(said["production"]) == [("Additional engineer", ["Benjamin Armbrister", "Jack Nuber"]),
                                        ("Remastering", ["George Marino"])]
    #? the real sample has performers on every song, so the band never stands in
    assert C.band_of(kept(REAL)) is None


# ----------------------------------------------------------------- case 2 (made): credits for the whole album

def test_the_album_s_own_performers_are_shown_on_the_album():
    found = kept(CASE2)
    track = C.place(found, C.Where(None, 1, 2, 3))
    said = C.answer(found, track, year=1999)
    assert said["level"] == "album"
    assert [(p["name"], p["did"]) for p in said["performers"]] == [
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

def test_with_no_credits_the_band_s_members_that_year_stand_in_and_never_on_the_song():
    found = kept(CASE3)
    assert C.band_of(found) == CASE3_ARTIST["id"]
    when = C.album_when(1978, {"originalReleaseDate": {"year": 1978}}, found)
    assert when == "1978-06-02"
    members = C.line_up(CASE3_ARTIST, when)
    said = C.answer(found, track_at(found, 1, 1), year=1978, members=members, band=CASE3_ARTIST["id"])
    #? its own level, which the app heads "The band in 1978" - never "song", which it words "on this song"
    assert said["level"] == "band" and said["level"] != "song"
    assert said["year"] == 1978 and said["recorded"] is None
    assert said["source_url"] == f"https://musicbrainz.org/artist/{CASE3_ARTIST['id']}"
    assert [(p["name"], p["did"]) for p in said["performers"]] == [
        ("Nan Voice", ["lead vocals"]),
        ("Rae Beat", ["drums", "background vocals"]),
        ("Ole Strings", ["guitar"]),
        ("Quin Low", ["bass guitar"]),
        ("Vic Guest", ["saxophone (additional)"]),
    ]
    #? left before (Pat), joined after (Sol), no dates (Tam), ended with no end date (Uma), and the supergroup the
    #? band is itself a member of - none of them
    assert not {"Pat Low", "Sol Later", "Tam Unknown", "Uma Gone", "The Made Supergroup"} & set(names(said["performers"]))


def test_with_only_the_year_known_a_member_who_joined_or_left_that_year_is_not_counted():
    #? no recording dates: the year alone, so Quin (joined Feb 1978) and Vic (May to July 1978) aren't sure
    bare = copy.deepcopy(CASE3)
    for t in bare["media"][0]["tracks"]:
        t["recording"]["first-release-date"] = ""
    found = kept(bare)
    when = C.album_when(1978, {"originalReleaseDate": {"year": 1978}}, found)
    assert when == "1978"
    assert names(C.line_up(CASE3_ARTIST, when)) == ["Nan Voice", "Rae Beat", "Ole Strings"]
    #? Navidrome's full original date is used when it has one
    assert C.album_when(1978, {"originalReleaseDate": {"year": 1978, "month": 6, "day": 30}}, found) == "1978-06-30"


def test_a_time_in_the_band_must_surely_cover_the_album_s_date():
    #? Back in Black, 25 July 1980: its singer joined that April; the singer before him died that February
    assert C.covers("1980-04", None, False, "1980-07-25")
    assert not C.covers("1974", "1980-02-19", True, "1980-07-25")
    #? with the year alone, neither is sure
    assert not C.covers("1980-04", None, False, "1980")
    assert not C.covers("1974", "1980-02-19", True, "1980")
    assert C.covers("1974", "1981", True, "1980")
    #? an unknown start, an end with no date, or no album date - never
    assert not C.covers(None, None, False, "1980-07-25")
    assert not C.covers("1974", None, True, "1980-07-25")
    assert not C.covers("1974", None, False, "")


def test_a_band_with_no_one_covering_the_year_is_none_and_a_credit_anywhere_rules_the_band_out():
    found = kept(CASE3)
    assert C.line_up(CASE3_ARTIST, "1960") == []
    assert C.answer(found, track_at(found, 1, 1), year=1960, members=[], band=CASE3_ARTIST["id"])["level"] == "none"
    #? one performer credit on one other song: the album has credits, so its line-up never stands in
    credited = copy.deepcopy(CASE3)
    credited["media"][0]["tracks"][3]["recording"]["relations"] = [CASE2["relations"][0]]
    assert C.band_of(kept(credited)) is None


# ----------------------------------------------------------------- case 4a and the answers with nothing

def test_nothing_at_all_is_none():
    found = kept(CASE4A)
    assert C.band_of(found) is None, "one Person: no band"
    said = C.answer(found, C.place(found, C.Where(None, 1, 1, 2)), year=2011)
    assert said == {**C.empty("none", 2011), "source_url": f"https://musicbrainz.org/release/{CASE4A['id']}"}


def test_every_answer_has_the_same_keys():
    assert set(C.empty("unmatched")) == set(C.empty("unavailable")) == KEYS
    assert set(C.LEVELS) == {"song", "album", "band", "none", "unmatched", "unavailable"}


# ----------------------------------------------------------------- the pairing

def test_a_song_is_placed_by_its_recording_id_first():
    found = kept(REAL)
    #? by recording, wherever Navidrome says it sits - and the disc's count doesn't matter then
    assert C.place(found, C.Where(BACK_IN_BLACK_SONG, None, None, 0))["position"] == 6
    #? an id the release doesn't carry is no pairing - never a fall back to the position
    assert C.place(found, C.Where("00000000-0000-4000-8000-000000000000", 1, 6, 10)) is None


def test_by_disc_and_track_only_when_the_disc_s_track_counts_agree():
    found = kept(REAL)
    assert C.place(found, C.Where(None, 1, 6, 10))["recording"] == BACK_IN_BLACK_SONG
    #? a folder with nine or eleven songs on the disc is not this release as it is: no pairing
    assert C.place(found, C.Where(None, 1, 6, 9)) is None
    assert C.place(found, C.Where(None, 1, 6, 11)) is None
    #? no such disc, no track number, a track past the end
    assert C.place(found, C.Where(None, 2, 1, 10)) is None
    assert C.place(found, C.Where(None, 1, None, 10)) is None
    assert C.place(found, C.Where(None, 1, 11, 10)) is None
    #? no disc number: the one disc of a one-disc release - never a guess between two
    assert C.place(found, C.Where(None, None, 6, 10))["recording"] == BACK_IN_BLACK_SONG
    two = kept(CASE2)
    assert C.place(two, C.Where(None, None, 1, 3)) is None
    assert C.place(two, C.Where(None, 2, 1, 2))["recording"] == "e2000001-0000-4000-8000-000000000001"
    assert C.place(two, C.Where(None, 2, 1, 3)) is None
    #? a disc MusicBrainz didn't list whole (a huge box set's) is never paired by position
    short = kept(REAL)
    short["media"][0]["track_count"] = 12
    assert C.place(short, C.Where(None, 1, 6, 10)) is None


def test_navidrome_s_song_and_album_say_where_the_song_sits():
    album = navidrome_album(BIB, 10)
    assert C.navidrome_place(album["song"][5], album) == C.Where(None, 1, 6, 10)
    #? a recording id from the file's tag, in any case; discNumber and track left out when unset; a disc counted
    tagged = {"discNumber": 2, "track": "3", "musicBrainzId": BACK_IN_BLACK_SONG.upper()}
    album = {"song": [{"discNumber": 2}, {"discNumber": 2}, {"discNumber": 1}, {}]}
    assert C.navidrome_place(tagged, album) == C.Where(BACK_IN_BLACK_SONG, 2, 3, 2)
    assert C.navidrome_place({}, album) == C.Where(None, None, None, 1)
    assert C.release_of({"musicBrainzId": BIB.upper()}) == BIB
    assert C.release_of({"musicBrainzId": "../../artist/x"}) is None and C.release_of({"musicBrainzId": ""}) is None


def test_the_album_s_year_is_its_original_year():
    found = kept(REAL)
    #? Navidrome's originalReleaseDate (the originaldate tag: original_year), never the pressing's 2003
    assert C.album_year({"originalReleaseDate": {"year": 1980}, "year": 2003}, found) == 1980
    #? no original date (an MP4 can't hold the tag): the recordings' first release, then the date tag
    assert C.album_year({"year": 2003}, found) == 1980
    assert C.album_year({"year": 2003}, None) == 2003
    assert C.album_year({}, None) is None


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
        "recordings+artist-credits+artist-rels+recording-level-rels+work-rels+work-level-rels")
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
    """MusicBrainz's lookups by endpoint, every request kept - `down` a 403 (asked once, no retries), `delay` slow."""

    def __init__(self, answers=None):
        self.answers = answers if answers is not None else {
            f"release/{BIB}": REAL, f"release/{CASE2['id']}": CASE2, f"release/{CASE3['id']}": CASE3,
            f"artist/{CASE3_ARTIST['id']}": CASE3_ARTIST, f"release/{CASE4A['id']}": CASE4A}
        self.calls: list[tuple[str, dict]] = []
        self.down = False
        self.delay = 0.0

    async def get(self, endpoint, params=None):
        self.calls.append((endpoint, dict(params or {})))
        if self.delay:
            await asyncio.sleep(self.delay)
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
    yield SimpleNamespace(app=app, client=TestClient(app), mb=mb, library=library, tmp=tmp_path)
    run(navidrome.close_client())


def credits_of(env, song_id: str = "so-6") -> dict:
    answer = env.client.get(f"/deadwax/credits/song/{song_id}")
    assert answer.status_code == 200, answer.text
    return answer.json()


def test_the_route_answers_a_song_s_credits_in_its_shape(env):
    said = credits_of(env)
    assert set(said) == KEYS
    assert said["level"] == "song" and said["year"] == 1980
    assert [set(p) for p in said["performers"]] == [{"id", "name", "did"}] * 5
    assert [set(row) for row in said["written"] + said["production"]] == [{"job", "people"}] * 6
    assert all(set(person) == {"id", "name"} for row in said["production"] for person in row["people"])
    assert said["recorded"] == {"begin": "1980-04", "end": "1980-05", "words": "April to May 1980"}
    assert said["source_url"] == f"https://musicbrainz.org/release/{BIB}"
    assert said == answerable_copy(C.answer(kept(REAL), track_at(kept(REAL), 1, 6), year=1980))
    #? Navidrome asked for the song, then its album, by id alone; MusicBrainz once, with the credits' own inc
    assert env.library.calls == [("getSong", {"id": "so-6"}), ("getAlbum", {"id": "al-1"})]
    assert env.mb.calls == [(f"release/{BIB}", {"inc": CREDITS_INC, "fmt": "json"})]


def answerable_copy(said: dict) -> dict:
    return json.loads(json.dumps(said))


def test_a_folder_whose_disc_count_differs_is_never_paired_by_position(env):
    #? nine songs on the disc in Navidrome against the release's ten: the album's own answer, never track 6's
    env.library.add(navidrome_album(BIB, 9))
    said = credits_of(env)
    assert said["level"] == "album" and said["performers"] == [] and said["written"] == []
    assert "Tony Platt" not in json.dumps(said)


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

    env.library.add(navidrome_album(CASE3["id"], 4, year=1978))
    said = credits_of(env, "so-1")
    assert said["level"] == "band" and said["year"] == 1978 and names(said["performers"])[0] == "Nan Voice"
    #? the band's members come from the artist lookup the artist page already makes (ARTIST_INC)
    assert env.mb.calls[-1] == (f"artist/{CASE3_ARTIST['id']}", {"inc": MusicBrainzClient.ARTIST_INC, "fmt": "json"})

    env.library.add(navidrome_album(CASE4A["id"], 2, year=2011))
    assert credits_of(env, "so-1") == {**C.empty("none", 2011),
                                       "source_url": f"https://musicbrainz.org/release/{CASE4A['id']}"}


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


def test_musicbrainz_down_with_nothing_kept_is_unavailable_never_an_error(env):
    env.mb.down = True
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
    #? what is on disk is the parsed answer - 1.2 KB compressed, where MusicBrainz's whole answer is 9.3
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
    request = SimpleNamespace(app=env.app, state=SimpleNamespace())

    async def go():
        late = await route.song_credits(request, "so-6")
        while route._running:
            await asyncio.sleep(0.02)
        again = await route.song_credits(request, "so-6")
        return late, again

    late, again = run(go())
    assert late == C.empty("unavailable", 1980)
    #? the lookup went on behind the answer, and the next ask had it, MusicBrainz asked once in all
    assert again["level"] == "song" and len(env.mb.calls) == 1


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
