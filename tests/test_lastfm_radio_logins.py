"""
GET /deadwax/lastfm/radio (2.1.44, S5 - notes/lastfm.md "S5 - radio") with logins on: the scope as the asker. Over
tests/test_navidrome_shuffle.py's Shuffler - step 6's Navidrome, shaped from 0.64.2's source, token auth checked for
real, every call kept with who made it - holding tests/test_lastfm.py's SHAPED LIBRARY, and tests/test_lastfm_routes.py's
stand-in Last.fm (recorded answers, and tests/test_lastfm_radio.py's SHAPED ones).

  - `yours` is the songs of the albums the asker starred, asked as them - never the store's;
  - `store` is the store, asked as the asker; the break-glass admin's `yours` is the store (no library of its own);
  - a session Navidrome ended is a 401, as everywhere; signed out, a 401;
  - the radio and the Shuffle read the scope's songs once between them.
"""

import httpx
import pytest
from fastapi.testclient import TestClient

from src import auth
from src.api import lastfm_endpoint
from src.api.lastfm_endpoint import lastfm
from src.config import Config
from src.routes import lastfm as route
from tests import test_lastfm_routes as T
from tests import test_navidrome_shuffle, test_personal_libraries
from tests.test_lastfm import LIBRARY
from tests.test_lastfm_radio import NOON, PATH, SEED, ids, made, radio_lastfm
from tests.test_personal_libraries import run, signed_in

#? the fixtures these build on, bound here as tests/test_navidrome_shuffle.py binds `on`
on = test_personal_libraries.on
shuffling = test_navidrome_shuffle.shuffling


@pytest.fixture
def as_you(shuffling, monkeypatch):
    """Step 6's Navidrome (tests/test_navidrome_shuffle.py's Shuffler) holding LIBRARY, with logins on, and the
    stand-in Last.fm."""
    fake = shuffling.fake
    fake.library = [dict(song) for song in LIBRARY]
    fake.albums.clear()
    for song in LIBRARY:
        fake.albums[song["albumId"]] = {"id": song["albumId"], "name": song["album"], "artist": song["artist"],
                                        "musicBrainzId": ""}
    monkeypatch.setattr(Config, "LASTFM_API_KEY", T.KEY)
    monkeypatch.setattr(lastfm_endpoint, "PER_SECOND", 1000)
    monkeypatch.setattr(route, "clock", lambda: NOON)
    shuffling.lastfm = radio_lastfm()
    lastfm._client = None
    lastfm.transport = httpx.MockTransport(shuffling.lastfm.handle)
    yield shuffling
    run(lastfm.close_client())
    lastfm._client = None
    lastfm.transport = None
    lastfm.refusal = None
    lastfm.refused_since = 0.0
    lastfm._retrying = False
    lastfm.limited_until = 0.0
    lastfm._starts.clear()
    lastfm._in_flight = 0
    assert shuffling.lastfm.unmatched == []


def test_yours_is_only_the_askers_library_asked_as_them(as_you):
    #? ethan's library: MGMT's Oracular Spectacular and Pond's The Weather
    as_you.fake.starred("ethan").update({"al-Oracular Spectacular", "al-The Weather"})
    as_you.fake.starred("james").add("al-Currents")
    ethan = signed_in(as_you, "ethan")
    response = ethan.get(PATH, params={**SEED, "scope": "yours"})
    assert response.status_code == 200, response.text
    got = response.json()
    theirs = [song for song in LIBRARY if song["albumId"] in {"al-Oracular Spectacular", "al-The Weather"}]
    assert got["songs"] == made(songs=theirs, user="ethan")
    assert set(ids(got)) == {"so-kids", "so-ttp", "so-silver", "so-sixteen"}
    assert {song["albumId"] for song in got["songs"]} <= {"al-Oracular Spectacular", "al-The Weather"}
    assert {user for user, _ in as_you.fake.asked("search3")} == {"ethan"}
    assert {user for user, _ in as_you.fake.asked("getAlbumList2")} == {"ethan"}


def test_the_store_is_the_store_asked_as_the_asker(as_you):
    response = signed_in(as_you, "ethan").get(PATH, params=SEED)
    assert response.status_code == 200, response.text
    assert response.json()["songs"] == made(user="ethan")
    assert {user for user, _ in as_you.fake.asked("search3")} == {"ethan"}
    assert as_you.fake.asked("getAlbumList2") == []


def test_the_break_glass_admins_yours_is_the_store(as_you):
    glass = signed_in(as_you, auth.BREAK_GLASS_USER)
    response = glass.get(PATH, params={**SEED, "scope": "yours"})
    assert response.status_code == 200, response.text
    assert response.json()["songs"] == made(user=auth.BREAK_GLASS_USER)
    assert as_you.fake.asked("getAlbumList2") == []


def test_a_session_navidrome_ended_is_a_401(as_you):
    ethan = signed_in(as_you, "ethan")
    as_you.fake.passwords["ethan"] = "changed in Navidrome"
    response = ethan.get(PATH, params=SEED)
    assert response.status_code == 401
    assert TestClient(as_you.app).get(PATH, params=SEED).status_code == 401


def test_a_radio_reads_navidrome_no_more_than_a_shuffle(as_you):
    ethan = signed_in(as_you, "ethan")
    assert ethan.get(PATH, params=SEED).status_code == 200
    assert ethan.get("/deadwax/navidrome/shuffle?scope=store").status_code == 200
    assert len(as_you.fake.asked("search3")) == 1
