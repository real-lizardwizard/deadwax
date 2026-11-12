"""
A song's lyrics for Now Playing (2.1.5) - routes/navidrome.py's `GET /deadwax/navidrome/lyrics/{song_id}`, and the
pure src/lyrics.py song_lyrics() that shapes its answer.

Through the whole app start() builds (no lifespan), against a fake Navidrome answering getLyricsBySongId as v0.64.2
does (server/subsonic/lyrics.go, responses.go): `lyricsList.structuredLyrics[]`, each entry `{displayArtist,
displayTitle, lang, line: [{start?, value}], offset?, synced}` - `start` in milliseconds, absent on a plain line -
and `lyricsList: {}` for a song with none. SNAPSHOT below is the shape of Navidrome's own snapshot ("Responses
LyricsList with data should match .JSON": two entries, `offset: 100`, one synced at 18800 and 22801, one plain),
its words our own.

What these hold:

  - THE RULES of song_lyrics(), one by one: which entry (the first synced one with words, else the first with
    words, else none); times (seconds, the offset taken off, held at 0, rounded to the millisecond, never
    LYRICS_LEAD_MS); synced or plain decided by the lines (a worded line untimed, or every worded line at one
    time, is plain); synced lines sorted, a timed empty line kept as a break; text (trailing spaces off, a
    newline kept); plain lyrics' edge blank lines dropped; bounded (LYRICS_LINES_MAX, LYRICS_TEXT_MAX).
  - NONE IS A 200 with no lines - never a 404, which is kept for a song Navidrome won't give the asker.
  - ONE CALL, THE ID ALONE: only getLyricsBySongId, with only `id` from the page - never `enhanced`, never a
    query parameter it sent; the login laid over last.
  - FAILURES as every player route says them: 70 a 404 (in Navidrome's words, which the apps never show - they
    pass SONG_GONE), a refused login mid-session the 401 that ends it, not set up a 503, an id past ID_MAX a 422
    with nothing asked, Navidrome down or not Subsonic a 502.
  - AN ETAG: a 304 with no body when unchanged; a changed `.lrc` (the fake's answer changed) a 200 and a new tag.
"""

import asyncio
import sys
from pathlib import Path

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from fastapi.testclient import TestClient  # noqa: E402

from src import auth, lyrics  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import SUBSONIC_ERRORS, navidrome  # noqa: E402
from src.config import Config  # noqa: E402
from src.lyrics import LYRICS_LINES_MAX, LYRICS_TEXT_MAX, song_lyrics  # noqa: E402
from src.routes.navidrome import ID_MAX  # noqa: E402
from test_navidrome import failed, ok  # noqa: E402
from test_navidrome_search import query  # noqa: E402
from tests import test_personal_libraries, test_player_as_you  # noqa: E402
from tests.test_personal_libraries import signed_in  # noqa: E402

#? step 5's and step 6's fixtures (logins on, the fake Navidrome checking token auth) for the 401 and the asker
on = test_personal_libraries.on
player = test_player_as_you.player

LYRICS = "/deadwax/navidrome/lyrics"

#? Navidrome's own snapshot's shape - two entries, offset 100, one synced at 18800 and 22801, one plain
SNAPSHOT = {"structuredLyrics": [
    {"displayArtist": "Some Artist", "displayTitle": "Some Song", "lang": "eng", "offset": 100, "synced": True,
     "line": [{"start": 18800, "value": "The first line we sing"}, {"start": 22801, "value": "And then the second"}]},
    {"displayArtist": "Some Artist", "displayTitle": "Some Song", "lang": "xxx", "offset": 100, "synced": False,
     "line": [{"value": "The first line we sing"}, {"value": "And then the second"}]},
]}


def entry(lines: list, synced: bool = True, **more) -> dict:
    """One structuredLyrics entry; `lines` as (start or None, value) pairs."""
    return {"displayArtist": "A", "displayTitle": "B", "lang": "xxx", "synced": synced, **more,
            "line": [{"value": value} if start is None else {"start": start, "value": value} for start, value in lines]}


def answer(*entries) -> dict:
    """getLyricsBySongId's body as the route's client hands it on: the inside of the Subsonic answer."""
    return {"status": "ok", "lyricsList": {"structuredLyrics": list(entries)}}


NONE = {"synced": False, "lines": []}


# ---------------------------------------------------------------- song_lyrics(), pure: the rules one by one

def test_synced_lines_are_in_seconds_with_the_offset_taken_off():
    assert song_lyrics({"lyricsList": SNAPSHOT}) == {"synced": True, "lines": [
        {"time": 18.7, "text": "The first line we sing"}, {"time": 22.701, "text": "And then the second"}]}


def test_times_are_rounded_to_the_millisecond():
    shaped = song_lyrics(answer(entry([(1000.4, "one"), (2000.6, "two")])))

    assert [line["time"] for line in shaped["lines"]] == [1.0, 2.001]


def test_synced_lines_are_sorted_stably_and_a_timed_empty_line_is_kept_as_a_break():
    shaped = song_lyrics(answer(entry([(0, ""), (9000, "third"), (3000, "first"), (6000, ""), (3000, "first too"),
                                       (5000, "second")])))

    assert shaped == {"synced": True, "lines": [
        {"time": 0.0, "text": ""}, {"time": 3.0, "text": "first"}, {"time": 3.0, "text": "first too"},
        {"time": 5.0, "text": "second"}, {"time": 6.0, "text": ""}, {"time": 9.0, "text": "third"}]}


def test_synced_lyrics_keep_their_empty_lines_at_either_end():
    shaped = song_lyrics(answer(entry([(0, ""), (1000, "a"), (2000, "b"), (3000, "")])))

    assert [line["text"] for line in shaped["lines"]] == ["", "a", "b", ""]


def test_an_untimed_empty_line_inside_synced_lyrics_is_dropped():
    shaped = song_lyrics(answer(entry([(1000, "a"), (None, ""), (2000, "b")])))

    assert shaped == {"synced": True, "lines": [{"time": 1.0, "text": "a"}, {"time": 2.0, "text": "b"}]}


def test_the_first_synced_entry_is_chosen_over_a_plain_one_listed_before_it():
    shaped = song_lyrics(answer(entry([(None, "plain words")], synced=False), entry([(1000, "timed"), (2000, "words")])))

    assert shaped["synced"] is True and [line["text"] for line in shaped["lines"]] == ["timed", "words"]


def test_the_first_entry_with_words_is_chosen_over_an_empty_one():
    shaped = song_lyrics(answer(entry([(1000, ""), (2000, "  ")]), entry([(None, "words")], synced=False),
                                entry([(None, "later words")], synced=False)))

    assert shaped == {"synced": False, "lines": [{"time": None, "text": "words"}]}


def test_of_two_synced_entries_the_first_is_chosen():
    shaped = song_lyrics(answer(entry([(1000, "one"), (2000, "two")]), entry([(1000, "uno"), (2000, "dos")])))

    assert [line["text"] for line in shaped["lines"]] == ["one", "two"]


def test_plain_lyrics_have_every_time_null_in_the_files_order():
    shaped = song_lyrics(answer(entry([(None, "zebra"), (None, "apple"), (None, "mango")], synced=False)))

    assert shaped == {"synced": False, "lines": [
        {"time": None, "text": "zebra"}, {"time": None, "text": "apple"}, {"time": None, "text": "mango"}]}


def test_plain_lyrics_keep_a_joined_lines_newline_and_lose_their_edge_blank_lines():
    shaped = song_lyrics(answer(entry([(None, ""), (None, " "), (None, "a line\nits joined line"), (None, ""),
                                       (None, "the last"), (None, ""), (None, "  ")], synced=False)))

    assert shaped == {"synced": False, "lines": [
        {"time": None, "text": "a line\nits joined line"}, {"time": None, "text": ""},
        {"time": None, "text": "the last"}]}


def test_trailing_spaces_come_off_each_of_a_lines_own_lines_and_nothing_else_changes():
    shaped = song_lyrics(answer(entry([(1000, "  led in, kept  \n  and its second   "), (2000, "Ünïcode ✓\t")])))

    assert [line["text"] for line in shaped["lines"]] == ["  led in, kept\n  and its second", "Ünïcode ✓"]


def test_a_newline_inside_a_synced_value_is_kept():
    shaped = song_lyrics(answer(entry([(1000, "sung\nand joined on"), (2000, "next")])))

    assert shaped["lines"][0] == {"time": 1.0, "text": "sung\nand joined on"}


def test_a_negative_result_is_held_at_zero():
    shaped = song_lyrics(answer(entry([(50, "early"), (1000, "on time")], offset=200)))

    assert [line["time"] for line in shaped["lines"]] == [0.0, 0.8]


def test_a_negative_offset_moves_lines_later():
    shaped = song_lyrics(answer(entry([(1000, "a"), (2000, "b")], offset=-500)))

    assert [line["time"] for line in shaped["lines"]] == [1.5, 2.5]


def test_an_offset_that_isnt_a_number_is_none():
    for offset in ("100", True, None, [100]):
        shaped = song_lyrics(answer(entry([(1000, "a"), (2000, "b")], offset=offset)))
        assert [line["time"] for line in shaped["lines"]] == [1.0, 2.0], offset


def test_the_lead_is_never_applied(monkeypatch):
    """LYRICS_LEAD_MS is already in the timestamps of every file deadwax wrote: applied again, it moves them twice."""
    monkeypatch.setattr(Config, "LYRICS_LEAD_MS", 400, raising=False)

    assert song_lyrics({"lyricsList": SNAPSHOT})["lines"][0]["time"] == 18.7


def test_synced_with_an_untimed_worded_line_is_answered_as_plain():
    shaped = song_lyrics(answer(entry([(1000, "a"), (None, "b"), (3000, "c")])))

    assert shaped == {"synced": False, "lines": [
        {"time": None, "text": "a"}, {"time": None, "text": "b"}, {"time": None, "text": "c"}]}


@pytest.mark.parametrize("stamp", [0, 12000])
def test_synced_with_every_worded_line_at_one_time_is_answered_as_plain(stamp):
    """LRCLIB holds some files stamped all at 0:00 - lit, the first line would be lit for the whole song."""
    shaped = song_lyrics(answer(entry([(0, ""), (stamp, "a"), (stamp, "b"), (stamp, "c")])))

    assert shaped == {"synced": False, "lines": [
        {"time": None, "text": "a"}, {"time": None, "text": "b"}, {"time": None, "text": "c"}]}


def test_one_time_is_judged_after_the_offset():
    """Two stamps the offset's hold at 0 brings together are one time, as lit."""
    shaped = song_lyrics(answer(entry([(50, "a"), (80, "b")], offset=100)))

    assert shaped["synced"] is False


def test_two_worded_lines_at_one_time_and_a_third_later_stay_synced():
    """A duet's shared stamp - two voices written once each."""
    shaped = song_lyrics(answer(entry([(1000, "she sings"), (1000, "he sings"), (4000, "they sing")])))

    assert shaped["synced"] is True
    assert [(line["time"], line["text"]) for line in shaped["lines"]] == [
        (1.0, "she sings"), (1.0, "he sings"), (4.0, "they sing")]


def test_an_entry_that_says_synced_is_judged_by_its_lines_and_a_later_one_that_can_be_lit_is_chosen():
    shaped = song_lyrics(answer(entry([(0, "all"), (0, "at zero")]), entry([(1000, "really"), (2000, "timed")])))

    assert shaped == {"synced": True, "lines": [{"time": 1.0, "text": "really"}, {"time": 2.0, "text": "timed"}]}


@pytest.mark.parametrize("body", [
    {"lyricsList": {}},
    {},
    {"lyricsList": None},
    {"lyricsList": {"structuredLyrics": "not a list"}},
    {"lyricsList": {"structuredLyrics": []}},
    {"lyricsList": {"structuredLyrics": [entry([(1000, ""), (2000, "   ")]), entry([(None, "")], synced=False)]}},
    {"lyricsList": {"structuredLyrics": ["junk", 3, None, {"line": "junk"}, {"line": [None, "x", 5]}]}},
    "not a dict",
])
def test_none_is_not_synced_with_no_lines(body):
    assert song_lyrics(body) == NONE


def test_lines_that_arent_lines_are_left_out():
    shaped = song_lyrics(answer({"synced": True, "line": [None, "x", {"start": 1000, "value": "a"},
                                                          {"start": "2000", "value": "b"}, {"start": 3000, "value": 5},
                                                          {"start": True, "value": "c"}, {"start": 4000, "value": "d"}]}))

    #? a start that isn't a number is no start: "b" and "c" untimed, so the whole entry is plain; a value that isn't
    #? text is an empty line
    assert shaped == {"synced": False, "lines": [{"time": None, "text": "a"}, {"time": None, "text": "b"},
                                                 {"time": None, "text": ""}, {"time": None, "text": "c"},
                                                 {"time": None, "text": "d"}]}


def test_display_artist_title_and_lang_arent_passed_on():
    shaped = song_lyrics({"lyricsList": SNAPSHOT})

    assert set(shaped) == {"synced", "lines"}
    assert all(set(line) == {"time", "text"} for line in shaped["lines"])


def test_at_most_lyrics_lines_max_lines():
    shaped = song_lyrics(answer(entry([(n * 1000, f"line {n}") for n in range(LYRICS_LINES_MAX + 1)])))

    assert LYRICS_LINES_MAX == 2000 and len(shaped["lines"]) == 2000
    assert shaped["lines"][-1]["text"] == "line 1999"


def test_a_line_is_cut_at_lyrics_text_max_characters():
    shaped = song_lyrics(answer(entry([(None, "x" * 5000), (None, "short")], synced=False)))

    assert LYRICS_TEXT_MAX == 1000 and shaped["lines"][0]["text"] == "x" * 1000 and shaped["lines"][1]["text"] == "short"


# ---------------------------------------------------------------- the route, against a fake Navidrome

@pytest.fixture
def upstream(monkeypatch):
    """Navidrome, answering from a handler each test sets. Every request it saw is kept."""
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
    seen: list[httpx.Request] = []
    state = {"handler": lambda request: httpx.Response(200, json=ok(lyricsList=SNAPSHOT))}

    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return state["handler"](request)

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest")
    yield state, seen
    asyncio.run(navidrome.close_client())


@pytest.fixture
def client():
    """The whole app, as uvicorn serves it, without its lifespan: nothing connects anywhere."""
    return TestClient(start())


def answering(state, lyrics_list) -> None:
    state["handler"] = lambda request: httpx.Response(200, json=ok(lyricsList=lyrics_list))


def test_the_route_answers_the_songs_lyrics_in_deadwaxs_own_shape(upstream, client):
    response = client.get(f"{LYRICS}/so-1")

    assert response.status_code == 200
    assert response.json() == song_lyrics({"lyricsList": SNAPSHOT})


def test_only_getlyricsbysongid_is_asked_with_the_id_alone(upstream, client):
    _, seen = upstream

    client.get(f"{LYRICS}/so-1?enhanced=true&id=other&u=admin&t=forged&s=salt&f=xml&c=evil&musicFolderId=3")

    [request] = seen
    assert request.url.path == "/rest/getLyricsBySongId"
    sent = query(request)
    assert sent["id"] == "so-1", "the id is the path's, never a query's"
    assert set(sent) == {"id", "u", "t", "s", "v", "c", "f"}, "no `enhanced`, nothing the page sent"
    assert sent["u"] == "james" and sent["t"] != "forged" and sent["s"] != "salt"
    assert sent["f"] == "json" and sent["c"] == "deadwax"


def test_an_id_with_query_characters_is_one_value(upstream, client):
    _, seen = upstream

    client.get(f"{LYRICS}/x%26enhanced%3Dtrue")

    sent = query(seen[0])
    assert sent["id"] == "x&enhanced=true" and "enhanced" not in sent


@pytest.mark.parametrize("lyrics_list", [{}, {"structuredLyrics": []}, {"structuredLyrics": [entry([(1000, "")])]}])
def test_none_is_a_200_with_no_lines(upstream, client, lyrics_list):
    state, _ = upstream
    answering(state, lyrics_list)

    response = client.get(f"{LYRICS}/so-1")

    assert response.status_code == 200 and response.json() == NONE


def test_a_missing_lyrics_list_is_none(upstream, client):
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=ok())

    response = client.get(f"{LYRICS}/so-1")

    assert response.status_code == 200 and response.json() == NONE


def test_a_song_navidrome_hasnt_got_for_them_is_a_404_in_navidromes_words(upstream, client):
    """The apps never show these words to a listener: they pass SONG_GONE for a not-found."""
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json=failed(70, "Song not found"))

    response = client.get(f"{LYRICS}/so-9")

    assert response.status_code == 404 and response.json()["detail"] == SUBSONIC_ERRORS[70]


def test_not_set_up_is_a_503_naming_the_settings(monkeypatch, client):
    monkeypatch.setattr(Config, "NAVIDROME_URL", None)

    response = client.get(f"{LYRICS}/so-1")

    assert response.status_code == 503 and "Server settings (Connections)" in response.json()["detail"]


def test_navidrome_down_is_a_502(upstream, client):
    state, _ = upstream

    def down(request):
        raise httpx.ConnectError("connection refused")

    state["handler"] = down

    response = client.get(f"{LYRICS}/so-1")

    assert response.status_code == 502 and "couldn't be reached" in response.json()["detail"]


def test_an_answer_that_isnt_subsonics_is_a_502(upstream, client):
    state, _ = upstream
    state["handler"] = lambda request: httpx.Response(200, json={"hello": "world"})

    response = client.get(f"{LYRICS}/so-1")

    assert response.status_code == 502 and "wasn't a Subsonic one" in response.json()["detail"]


def test_an_id_longer_than_any_of_navidromes_is_a_422_and_never_asked(upstream, client):
    _, seen = upstream

    assert client.get(f"{LYRICS}/{'x' * (ID_MAX + 1)}").status_code == 422
    assert seen == []


def test_the_longest_id_is_allowed(upstream, client):
    _, seen = upstream

    assert client.get(f"{LYRICS}/{'x' * ID_MAX}").status_code == 200
    assert query(seen[0])["id"] == "x" * ID_MAX


def test_the_answer_carries_an_etag_and_an_unchanged_one_is_a_304_with_no_body(upstream, client):
    first = client.get(f"{LYRICS}/so-1")
    again = client.get(f"{LYRICS}/so-1")
    held = client.get(f"{LYRICS}/so-1", headers={"If-None-Match": first.headers["etag"]})

    assert first.headers["cache-control"] == "no-cache" and first.headers["etag"].startswith('"')
    assert again.headers["etag"] == first.headers["etag"]
    assert held.status_code == 304 and held.content == b"" and held.headers["etag"] == first.headers["etag"]


def test_a_changed_lrc_is_a_200_with_a_new_etag(upstream, client):
    state, _ = upstream
    first = client.get(f"{LYRICS}/so-1")
    #? a re-time: Navidrome reads the sidecar from disk on every ask, so the next answer is the new file's
    answering(state, {"structuredLyrics": [entry([(18000, "The first line we sing"), (22000, "And then the second")])]})

    after = client.get(f"{LYRICS}/so-1", headers={"If-None-Match": first.headers["etag"]})

    assert after.status_code == 200 and after.headers["etag"] != first.headers["etag"]
    assert [line["time"] for line in after.json()["lines"]] == [18.0, 22.0]


def test_the_route_reads_no_file_and_writes_nothing(upstream, client, monkeypatch):
    """Navidrome alone: no `.lrc` read by deadwax, nothing asked of LRCLIB, nothing written."""
    for name in ("read_track_lyrics", "plan_lyrics", "execute_lyrics", "fetch_album_lyrics", "embedded_lyrics"):
        monkeypatch.setattr(lyrics, name, lambda *a, **k: pytest.fail(f"{name} was called"))

    assert client.get(f"{LYRICS}/so-1").status_code == 200


# ---------------------------------------------------------------- as the asker, logins on

def test_with_logins_on_it_asks_as_the_signed_in_user(player):
    ethan = signed_in(player, "ethan")
    player.fake.forget()

    response = ethan.get(f"{LYRICS}/{test_player_as_you.SONG}")

    assert response.status_code == 200
    assert response.json() == {"synced": True, "lines": [
        {"time": 0.0, "text": ""}, {"time": 1.5, "text": "The first line"}, {"time": 4.0, "text": "The second line"}]}
    assert player.fake.by() == [("ethan", "getLyricsBySongId")]


def test_a_song_navidrome_keeps_from_them_is_a_404(player):
    player.fake.hidden["ethan"] = {test_player_as_you.SONG}

    assert signed_in(player, "ethan").get(f"{LYRICS}/{test_player_as_you.SONG}").status_code == 404
    assert signed_in(player, "james").get(f"{LYRICS}/{test_player_as_you.SONG}").status_code == 200


def test_a_refused_login_is_the_401_that_ends_the_session(player):
    ethan = signed_in(player, "ethan")
    player.fake.passwords["ethan"] = "changed"

    response = ethan.get(f"{LYRICS}/{test_player_as_you.SONG}")

    assert response.status_code == 401 and response.json()["detail"] == auth.LOGIN_GONE
    asked = len(player.fake.calls)
    assert ethan.get(f"{LYRICS}/{test_player_as_you.SONG}").status_code == 401
    assert len(player.fake.calls) == asked, "nothing after the refusal asks Navidrome again"


def test_with_logins_on_lyrics_need_a_session(player):
    assert TestClient(player.app).get(f"{LYRICS}/{test_player_as_you.SONG}").status_code == 401
    assert player.fake.by("getLyricsBySongId") == []
