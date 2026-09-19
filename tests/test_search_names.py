"""
Searching Soulseek for an artist who has renamed.

Soulseek needs every word of a query somewhere in a share's path, so a search under one name
cannot find a share filed under another. Ye's Donda is credited "Kanye West" and BULLY "Ye", and
people share each under both - by what the album said when they got it, or by what they file
that artist under now. The matcher never looks at the artist (its signals are the tracks), so
the only place a name decides anything is the query, and that is what these pin.

Nothing here talks to slskd or MusicBrainz; the payloads are their documented shapes, and Ye's
aliases are trimmed from the live API.
"""

import asyncio
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest  # noqa: E402

from src.api.slskd_endpoint import SlskdClient, SlskdSearchRefused  # noqa: E402
from src.artists import former_names  # noqa: E402
from src.matching import group_files_by_directory  # noqa: E402
from src.routes import download  # noqa: E402
from tests.test_slskd_errors import NOT_CONNECTED_BODY, refusal  # noqa: E402

YE_ID = "164f0d73-1234-4e2c-8743-d77bf2191051"

#? trimmed from artist/164f0d73...?inc=aliases on the live API
YE = {"id": YE_ID, "name": "Ye", "aliases": [
    {"name": "Kanye", "type": "Artist name", "ended": False},
    {"name": "Kanye Omari West", "type": "Legal name", "ended": True, "end": "2021-10-18"},
    {"name": "Kanye West", "type": "Artist name", "primary": True, "locale": "zh", "ended": False},
    {"name": "Kanye West", "type": "Artist name", "ended": True, "end": "2024"},
    {"name": "Kayne West", "type": "Search hint", "ended": False},
    {"name": "Ye", "type": "Artist name", "primary": True, "locale": "en", "ended": False},
    {"name": "Yeezy", "type": "Artist name", "ended": False},
]}


# ── which names ─────────────────────────────────────────────────────────────────────────────

def test_a_former_name_is_one_musicbrainz_itself_marks_as_former():
    #? an ENDED "Artist name" alias - not a nickname, a legal name, a typo or a locale spelling,
    #? none of which anyone names a folder after, and each of which would cost a search
    assert former_names(YE) == ["Kanye West"]


def test_an_artist_who_never_renamed_has_no_former_names():
    assert former_names({"name": "Portishead", "aliases": [
        {"name": "Portishead", "type": "Artist name", "ended": False}]}) == []
    assert former_names(None) == [] and former_names({"error": "busy"}) == []


def test_donda_is_searched_under_its_credit_and_the_name_he_goes_by_now():
    assert download.search_names("Kanye West", "Ye") == ["Kanye West", "Ye"]


def test_bully_is_searched_under_his_former_name_as_well():
    #? credited Ye and called Ye, so the release alone never mentions Kanye West
    assert download.search_names("Ye", "Ye", ["Kanye West"]) == ["Ye", "Kanye West"]


def test_an_artist_who_never_renamed_is_exactly_one_search():
    assert download.search_names("Portishead", "Portishead", []) == ["Portishead"]
    assert download.search_names("Portishead", "portishead ", None) == ["Portishead"]


# ── one share found twice ───────────────────────────────────────────────────────────────────

def test_a_share_found_by_two_searches_is_counted_once():
    """Its tracks would otherwise count double, and every file would be enqueued twice."""
    share = {"username": "bob", "files": [
        {"filename": "@@bob\\Kanye West\\Ye - Donda\\01 Donda Chant.flac", "size": 1},
        {"filename": "@@bob\\Kanye West\\Ye - Donda\\02 Jail.flac", "size": 2},
    ]}
    candidates = group_files_by_directory([share, dict(share)])
    assert len(candidates) == 1
    assert len(candidates[0]["files"]) == 2


def test_two_users_sharing_the_same_path_are_still_two_candidates():
    one = {"username": "bob", "files": [{"filename": "Ye\\Donda\\01.flac", "size": 1}]}
    two = {"username": "sue", "files": [{"filename": "Ye\\Donda\\01.flac", "size": 1}]}
    assert len(group_files_by_directory([one, two])) == 2


# ── running them ────────────────────────────────────────────────────────────────────────────

class RecordingSearches:
    """slskd's searches API, recording the order things happen in."""

    def __init__(self, refuse=None):
        self.refuse = refuse or {}
        self.log = []
        self.deleted = []

    def search_text(self, searchText, **kwargs):
        self.log.append(("start", searchText))
        if searchText in self.refuse:
            raise self.refuse[searchText]
        return {"id": f"id:{searchText}"}

    def state(self, search_id):
        self.log.append(("state", search_id))
        return {"isComplete": True}

    def search_responses(self, search_id):
        return [{"username": f"peer-of-{search_id}", "files": []}]

    def delete(self, search_id):
        self.deleted.append(search_id)
        return True


def run_all(searches, queries, state=None):
    client = SlskdClient()
    client.client = SimpleNamespace(
        searches=searches,
        application=SimpleNamespace(state=lambda: state or {}),
    )
    return asyncio.run(client.search_all(queries, poll_interval=0, max_wait=1))


def test_every_search_is_started_before_any_is_waited_on():
    #? side by side - one after another, two names would cost two whole search timeouts
    searches = RecordingSearches()
    run_all(searches, ["Kanye West Donda", "Ye Donda"])
    starts = [i for i, (kind, _) in enumerate(searches.log) if kind == "start"]
    first_wait = next(i for i, (kind, _) in enumerate(searches.log) if kind == "state")
    assert len(starts) == 2 and max(starts) < first_wait


def test_the_answers_of_every_search_come_back_together_and_every_search_is_cleaned_up():
    searches = RecordingSearches()
    found = run_all(searches, ["Kanye West Donda", "Ye Donda"])
    assert [r["username"] for r in found] == ["peer-of-id:Kanye West Donda", "peer-of-id:Ye Donda"]
    assert searches.deleted == ["id:Kanye West Donda", "id:Ye Donda"]


def test_a_refusal_before_anything_is_running_is_the_answer():
    #? slskd logged out refuses every search alike, so the rest are not even asked
    searches = RecordingSearches(refuse={"Kanye West Donda": refusal(body=NOT_CONNECTED_BODY)})
    with pytest.raises(SlskdSearchRefused):
        run_all(searches, ["Kanye West Donda", "Ye Donda"])
    assert [q for kind, q in searches.log if kind == "start"] == ["Kanye West Donda"]


def test_a_refusal_once_one_is_running_narrows_the_search_rather_than_failing_it():
    searches = RecordingSearches(refuse={"Ye Donda": refusal(status=429, text="busy")})
    found = run_all(searches, ["Kanye West Donda", "Ye Donda"])
    assert [r["username"] for r in found] == ["peer-of-id:Kanye West Donda"]


# ── the route ───────────────────────────────────────────────────────────────────────────────

class FakeSlskd:
    def __init__(self):
        self.rounds = []

    async def search_all(self, queries):
        self.rounds.append(list(queries))
        return []


class FakeMusicBrainz:
    def __init__(self, artist=YE, delay=0.0):
        self.artist, self.delay, self.asked = artist, delay, []

    async def get_artist_aliases(self, mbid):
        self.asked.append(mbid)
        await asyncio.sleep(self.delay)
        return self.artist


class NoStore:
    async def peer_speeds(self, names):
        return {}


def find(body, musicbrainz=None):
    slskd = FakeSlskd()
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(
        slskd_client=slskd, musicbrainz_client=musicbrainz or FakeMusicBrainz(), store=NoStore(),
    )))
    answer = asyncio.run(download.find_candidates(request, download.FindCandidatesRequest(**body)))
    return answer, slskd


DONDA = {"artist": "Kanye West", "album_artist": "Ye", "artist_mbids": [YE_ID], "album": "Donda"}
BULLY = {"artist": "Ye", "album_artist": "Ye", "artist_mbids": [YE_ID], "album": "BULLY"}


def test_the_browser_sends_both_names_and_the_request_keeps_them():
    #? pydantic drops an undeclared field without a word; these were being dropped
    kept = download.FindCandidatesRequest(**DONDA).model_dump()
    assert kept["album_artist"] == "Ye" and kept["artist_mbids"] == [YE_ID]


def test_donda_searches_both_names_in_one_round():
    answer, slskd = find(DONDA)
    assert slskd.rounds == [["Kanye West Donda", "Ye Donda"]]
    #? his former name is Kanye West, which was already searched - no second round
    assert answer["queries"] == ["Kanye West Donda", "Ye Donda"]
    assert answer["query"] == "Kanye West Donda", "the credit is what goes in the box"


def test_bully_adds_his_former_name_in_a_second_round():
    answer, slskd = find(BULLY)
    assert slskd.rounds == [["Ye BULLY"], ["Kanye West BULLY"]]
    assert answer["queries"] == ["Ye BULLY", "Kanye West BULLY"]


def test_a_query_typed_by_hand_is_searched_exactly_as_typed_and_nothing_else():
    musicbrainz = FakeMusicBrainz()
    answer, slskd = find({**BULLY, "query_override": "ye bully flac"}, musicbrainz)
    assert slskd.rounds == [["ye bully flac"]] and musicbrainz.asked == []


def test_a_slow_musicbrainz_costs_the_former_names_and_nothing_else(monkeypatch):
    monkeypatch.setattr(download, "FORMER_NAMES_BUDGET_SECONDS", 0.05)
    answer, slskd = find(BULLY, FakeMusicBrainz(delay=2.0))
    assert slskd.rounds == [["Ye BULLY"]]
    assert answer["queries"] == ["Ye BULLY"]


def test_musicbrainz_answering_with_an_error_is_no_former_names():
    answer, slskd = find(BULLY, FakeMusicBrainz(artist={"error": "busy", "code": 503}))
    assert slskd.rounds == [["Ye BULLY"]]


def test_a_collaboration_is_not_expanded_name_by_name():
    #? each artist times each name multiplies; the credit and current names are searched already
    musicbrainz = FakeMusicBrainz()
    body = {"artist": "JAY-Z & Kanye West", "album_artist": "JAY-Z & Ye",
            "artist_mbids": ["jz", YE_ID], "album": "Watch the Throne"}
    answer, slskd = find(body, musicbrainz)
    assert musicbrainz.asked == []
    assert slskd.rounds == [["JAY-Z Kanye West Watch the Throne", "JAY-Z Ye Watch the Throne"]]


def test_a_search_that_finds_nothing_says_so_rather_than_crashing():
    #? the warning for an empty result named a variable that no longer existed
    answer, _ = find({"artist": "Portishead", "album": "Dummy"})
    assert answer["candidates"] == [] and answer["queries"] == ["Portishead Dummy"]
