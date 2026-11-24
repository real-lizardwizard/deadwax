"""
The keys a Last.fm title or name meets the library by (2.1.36, notes/lastfm.md; the design's 2.4), held to
tests/fixtures/lastfm/match-vectors.json - whose `key`s are the web TypeScript's own answers (songs.ts titleKey,
owned.ts foldName), written by tests/fixtures/lastfm/export-vectors.cjs. One contract for Python (radio, from 2.1.40)
and the iPhone app's Core (top songs): a title that keys differently in one of them is a song that matches on one
side only.
"""

import json
from pathlib import Path

import pytest

from src.lastfm import first_credit, match_key, name_key, strip_title, title_key

REPO = Path(__file__).resolve().parent.parent
VECTORS = REPO / "tests/fixtures/lastfm/match-vectors.json"
#? the iPhone app's copy, on the `ios` branch: byte for byte this one
APP_COPY = REPO / "ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lastfm/match-vectors.json"

DATA = json.loads(VECTORS.read_text(encoding="ascii"))


def test_there_are_enough_of_each():
    assert len(DATA["titles"]) >= 40
    assert len(DATA["names"]) >= 20


@pytest.mark.parametrize("case", DATA["titles"], ids=lambda case: case["title"])
def test_a_title_keys_as_the_web_keys_it(case):
    assert strip_title(case["title"]) == case["stripped"]
    assert title_key(case["stripped"]) == case["key"]
    assert match_key(case["title"]) == case["key"]


@pytest.mark.parametrize("case", DATA["names"], ids=lambda case: case["name"])
def test_a_name_folds_as_the_web_folds_it(case):
    assert name_key(case["name"]) == case["key"]
    assert first_credit(case["name"]) == case["first"]


def test_the_folds_that_matter_most():
    """Read off the vectors, so a case quietly rewritten to its new answer still fails here."""
    assert match_key("Let It Happen - 2015 Remaster") == match_key("Let It Happen")
    assert match_key("Roads (Live)") == match_key("Roads - Live") == match_key("Roads")
    assert match_key("Lost in Yesterday (feat. Someone Else)") == match_key("Lost in Yesterday")
    #? a remix, an edit, a radio edit and a demo stay songs of their own
    assert match_key("Roads (Max Cooper remix)") != match_key("Roads")
    assert match_key("Sour Times - Radio Edit") != match_key("Sour Times")
    assert match_key("Mysterons - Demo") != match_key("Mysterons")
    #? " with " is a title's, never a feature's, unbracketed
    assert match_key("Dancing with Myself") == "dancing with myself"
    #? a credit is never split at & or a comma
    assert first_credit("Simon & Garfunkel") == "Simon & Garfunkel"
    assert name_key("The Beatles") == name_key("Beatles")


def test_the_app_s_copy_is_this_one():
    if not APP_COPY.exists():
        pytest.skip("no iPhone app copy in this checkout")
    assert APP_COPY.read_bytes() == VECTORS.read_bytes()
