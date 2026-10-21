"""
Search what's saved (2.0.0-player.56) - src/saved_index.py, its place in src/musicbrainz_cache.SavedAnswers, and
GET /search_musicbrainz/saved.

James (2026-10-15): "and the cache includes songs and albums as well, correct? so i can search it all?" - an index of
everything MusicBrainz's saved answers mention, searched by any words. Every answer here is a real one recorded from
MusicBrainz (tests/fixtures/saved/, tests/fixtures/songs/, tests/fixtures/search/, trimmed), put into a scratch file
the way the disk layer puts it; MusicBrainz itself is never asked.

What it pins:

  - what each kind of answer the app asks for is read for: an album search, a song search, an artist search, an
    album's pressings with their tracklists, an artist page, a discography page - and nothing for a lookup of one
    release (no group to put its songs on) or an answer of a shape it doesn't know;
  - ONE row per thing however many answers mention it, the newest answer's fields winning and a field it doesn't
    carry keeping the older one's (a credit's partial artist never wipes an artist page's aliases);
  - a song seen only on a saved album page found by its title ("glory box" after Dummy's pressings alone);
  - the matching: every word, the last as a prefix (as you type), accents folded both ways (Björk = bjork), names and
    titles over credits, a name typed exactly lifted to the top, nothing typed read as FTS5's own syntax;
  - kept in step with the cache: a refresh replacing an answer, the size bound's trim and Clear each take what only
    those answers mention - and only that; the index's bytes count toward the budget;
  - 0 is off; a file 2.0.0-player.54 made (no index) read into one once, in the background, with one log line; a
    SQLite without FTS5 saving answers as ever with Search finding nothing saved; a slow search given up;
  - the route: a user's, its bounds, `available`, and its shapes the very ones /artists, /fully_search and /songs
    answer - so a saved row and a MusicBrainz row are one component.
"""

import asyncio
import hashlib
import json
import sqlite3
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from src import musicbrainz_cache, saved_index  # noqa: E402
from src.api.musicbrainz_endpoint import ResponseCache  # noqa: E402
from src.artists import artist_match, credit_name  # noqa: E402
from src.musicbrainz_cache import SavedAnswers  # noqa: E402
from src.routes import search_musicbrainz  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"
PORTISHEAD = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"
DUMMY = "48140466-cff6-3222-bd55-63c27e43190d"
#? ...as the index keeps them (a UUID's 16 bytes)
P_ID, D_ID = saved_index.stored_id(PORTISHEAD), saved_index.stored_id(DUMMY)


def recorded(name: str) -> tuple[str, dict, dict]:
    """A recorded answer in tests/fixtures/saved/: its endpoint, its params, its payload."""
    answer = json.loads((FIXTURES / "saved" / f"{name}.json").read_text())
    return answer["endpoint"], answer["params"], answer["payload"]


def fixture(path: str) -> dict:
    return json.loads((FIXTURES / path).read_text())


#? the app's own questions, for the answers recorded elsewhere in tests/fixtures
STUDIO = ("release-group/", {"query": '(artist:"Portishead") AND (primarytype:"Album" OR primarytype:"EP")', "fmt": "json", "limit": 12},
          fixture("search/rg-artist-portishead-studio.json"))
ROADS = ("recording/", {"query": 'recording:"roads" AND (artist:"Portishead" OR artistname:"Portishead")', "fmt": "json", "limit": 25},
         fixture("songs/roads-portishead.json"))
ARTISTS = ("artist/", {"query": '(artist:"portishead" OR alias:"portishead")', "fmt": "json", "limit": 10}, fixture("artists/portishead.json"))


class Clock:
    def __init__(self, now: float = 1_800_000_000.0):
        self.now = now

    def __call__(self) -> float:
        return self.now


@pytest.fixture
def saved(tmp_path):
    """A scratch file of saved answers, its clock moved by hand - closed after."""
    made = []

    def make(max_bytes: int = 50 << 20, path=None, clock=None) -> SavedAnswers:
        answers = SavedAnswers(path=str(path or tmp_path / "musicbrainz-cache.db"), max_bytes=max_bytes, clock=clock or Clock())
        made.append(answers)
        return answers

    yield make
    for answers in made:
        asyncio.run(answers.close())


def put(answers: SavedAnswers, *found: tuple[str, dict, dict]) -> None:
    for endpoint, params, payload in found:
        answers.put(ResponseCache.disk_key(endpoint, params), payload)
    asyncio.run(answers.flush())


def search(answers: SavedAnswers, words: str) -> dict | None:
    return asyncio.run(answers.search(words))


def names(found: dict) -> dict:
    return {
        "artists": [match["name"] for match in found["artists"]["matches"]],
        "albums": [group["title"] for group in found["albums"]["release-groups"]],
        "songs": [recording["title"] for recording in found["songs"]["recordings"]],
    }


def rows(path, table: str) -> int:
    with sqlite3.connect(path) as connection:
        return connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


# ------------------------------------------------------------------ what each answer is read for


def test_an_album_search_brings_its_albums_and_their_credited_artists():
    found = saved_index.read_answer(*STUDIO)
    assert {fields["title"] for fields in found.albums.values()} >= {"Dummy", "Third", "Portishead"}
    dummy = found.albums[DUMMY]
    assert dummy["primary_type"] == "Album" and dummy["first_release_date"] == "1994-08-22"
    assert credit_name(dummy["artist_credit"]) == "Portishead"
    assert found.artists[PORTISHEAD]["name"] == "Portishead"
    assert not found.songs and not found.releases


def test_a_song_search_brings_its_songs_the_pressings_they_are_on_and_their_albums():
    found = saved_index.read_answer(*ROADS)
    assert found.songs and all(fields["title"].startswith("Roads") for fields in found.songs.values())
    #? each release a recording is on: the pressing, its album (a recording's release carries its group), the track
    assert found.releases and all(fields["album"] in found.albums for fields in found.releases.values())
    some = next(iter(found.tracks.values()))
    assert some["number"] and some["length"]
    #? the group a recording's release carries has no credit of its own: the release's is kept, weakly
    album = next(iter(found.albums.values()))
    assert album["artist_credit"] is None and album["weak_credit"]


def test_an_artist_search_brings_each_artist_with_the_other_names_they_go_by():
    found = saved_index.read_answer(*recorded("bjork-artists"))
    bjork = next(fields for fields in found.artists.values() if fields["name"] == "Björk")
    assert "Biork" in bjork["aliases"] and bjork["type"] == "Person" and bjork["country"] == "IS"


def test_an_albums_pressings_bring_every_track_as_a_song_on_that_album():
    endpoint, params, payload = recorded("dummy-pressings")
    found = saved_index.read_answer(endpoint, params, payload)
    assert found.albums[DUMMY]["title"] == "Dummy"
    assert "Glory Box" in {fields["title"] for fields in found.songs.values()}
    assert {fields["album"] for fields in found.releases.values()} == {DUMMY}
    assert len(found.tracks) == sum(len(medium["tracks"]) for release in payload["releases"] for medium in release["media"])


def test_pressings_asked_without_their_group_are_put_on_the_group_asked_for():
    endpoint, params, payload = recorded("dummy-pressings")
    bare = {**payload, "releases": [{key: value for key, value in release.items() if key != "release-group"} for release in payload["releases"]]}
    found = saved_index.read_answer(endpoint, params, bare)
    assert {fields["album"] for fields in found.releases.values()} == {DUMMY}
    assert DUMMY not in found.albums, "no group read, so no album row - its songs are joined to one another answer made"


def test_an_artist_page_and_a_discography_page_are_read_too():
    page = saved_index.read_answer(*recorded("portishead-artist"))
    assert page.artists[PORTISHEAD]["begin"] == "1991" and page.artists[PORTISHEAD]["sort_name"] == "Portishead"
    discography = saved_index.read_answer(*recorded("portishead-discography"))
    assert "Third" in {fields["title"] for fields in discography.albums.values()}


@pytest.mark.parametrize("endpoint, params, payload", [
    ("release/0cfdeff7-4aa7-4df4-918d-88c9421cc512", {"inc": "media+recordings", "fmt": "json"}, {"id": "x", "media": [{"tracks": [{"recording": {"id": "r"}}]}]}),
    ("release-group/f6b1b900-6108-32f0-abbd-2855af9151eb", {}, {"id": "f6b1b900", "title": "x"}),
    ("release-group/", {"query": "x"}, {"release-groups": "not a list"}),
    ("recording/", {"query": "x"}, ["not", "a", "dict"]),
])
def test_an_answer_it_doesnt_read_is_nothing_never_an_error(endpoint, params, payload):
    assert saved_index.read_answer(endpoint, params, payload).is_empty()


def test_ids_are_kept_as_sixteen_bytes_and_given_back_as_written():
    assert saved_index.stored_id(DUMMY) == bytes.fromhex(DUMMY.replace("-", ""))
    assert saved_index.given_id(saved_index.stored_id(DUMMY)) == DUMMY
    #? anything that isn't a UUID as MusicBrainz writes one is kept as it is
    for other in ("not-an-id", DUMMY.upper(), "{" + DUMMY + "}"):
        assert saved_index.stored_id(other) == other and saved_index.given_id(other) == other


def test_credit_name_is_the_apps_way_of_saying_a_credit():
    """ui/src/lib/release.ts creditName(): each name as credited, then its join phrase, trimmed - "Nickelus F &
    Portishead", as Search's row says it (ui/test/search.sim.cjs: "Mixtape · Nickelus F & Portishead · 2009")."""
    rare = next(group for group in STUDIO[2]["release-groups"] if group["title"].startswith("R.A.R.E"))
    assert credit_name(rare["artist-credit"]) == "Nickelus F & Portishead"
    assert credit_name([{"artist": {"name": "Portishead"}, "joinphrase": " feat. "}, {"name": "Beth"}]) == "Portishead feat. Beth"
    assert credit_name(None) == "" and credit_name([None, "x"]) == ""


# ------------------------------------------------------------------ one row per thing


def test_one_row_per_thing_however_many_answers_mention_it(saved):
    answers = saved()
    put(answers, STUDIO, recorded("portishead-discography"), recorded("dummy-pressings"), ARTISTS, recorded("portishead-artist"))
    with sqlite3.connect(answers.path()) as connection:
        assert connection.execute("SELECT COUNT(*) FROM saved_artists WHERE id = ?", (P_ID,)).fetchone()[0] == 1
        assert connection.execute("SELECT COUNT(*) FROM saved_albums WHERE id = ?", (D_ID,)).fetchone()[0] == 1
        mentions = connection.execute("SELECT COUNT(*) FROM saved_mentions WHERE kind = ? AND thing = "
                                      "(SELECT n FROM saved_artists WHERE id = ?)", (saved_index.ARTIST, P_ID)).fetchone()[0]
    assert mentions == 5, "every answer that mentions Portishead says so"
    assert search(answers, "portishead")["artists"]["matches"][0]["name"] == "Portishead"


def test_the_newest_answer_wins_and_what_it_doesnt_say_is_kept(saved):
    clock = Clock()
    answers = saved(clock=clock)
    put(answers, recorded("portishead-artist"))                     # their page: aliases, years
    clock.now += 60
    credit_only = ("release-group/", {"query": "x"}, {"release-groups": [{"id": DUMMY, "title": "Dummy (newer)",
                   "artist-credit": [{"name": "Portishead", "artist": {"id": PORTISHEAD, "name": "Portishead", "sort-name": "Portishead"}}]}]})
    put(answers, credit_only)                                       # a credit: no aliases, no years
    with sqlite3.connect(answers.path()) as connection:
        aliases, begin = connection.execute("SELECT aliases, begin FROM saved_artists WHERE id = ?", (P_ID,)).fetchone()
    assert json.loads(aliases) and begin == "1991", "a credit's partial artist never wipes what their page said"
    older = ("release-group/", {"query": "y"}, {"release-groups": [{"id": DUMMY, "title": "Dummy (older)", "primary-type": "Album"}]})
    clock.now -= 600
    put(answers, older)
    with sqlite3.connect(answers.path()) as connection:
        title, kind = connection.execute("SELECT title, primary_type FROM saved_albums WHERE id = ?", (D_ID,)).fetchone()
    assert title == "Dummy (newer)", "the newest answer's fields win"
    assert kind == "Album", "...and a field it didn't carry is filled from an older one"


# ------------------------------------------------------------------ searching


def test_a_song_seen_only_on_a_saved_album_page_is_found_by_its_title(saved):
    """James's example: search "portishead", open Dummy - then "glory box" asks MusicBrainz nothing."""
    answers = saved()
    put(answers, recorded("dummy-pressings"))
    found = search(answers, "glory box")
    #? two recordings - the 2008 remaster's pressing has its own - which the app makes one song (groupSongs)
    assert set(names(found)["songs"]) == {"Glory Box"}
    song = found["songs"]["recordings"][0]
    assert {release["release-group"]["id"] for release in song["releases"]} == {DUMMY}
    assert song["releases"][0]["media"][0]["track"][0]["title"] == "Glory Box"
    assert song["artist-credit"][0]["artist"]["id"] == PORTISHEAD


def test_every_word_must_match_the_last_as_you_type_it(saved):
    answers = saved()
    put(answers, STUDIO, recorded("dummy-pressings"), ARTISTS)
    assert names(search(answers, "portis"))["artists"] == ["Portishead"]
    assert set(names(search(answers, "glo"))["songs"]) == {"Glory Box"}
    assert set(names(search(answers, "glory bo"))["songs"]) == {"Glory Box"}
    assert set(names(search(answers, "portishead glory"))["songs"]) == {"Glory Box"}, "a word may match the credit"
    assert names(search(answers, "glory portishead roads")) == {"artists": [], "albums": [], "songs": []}, "every word"
    assert names(search(answers, "lory")) == {"artists": [], "albums": [], "songs": []}, "a prefix, never the middle of a word"


def test_accents_fold_both_ways(saved):
    answers = saved()
    put(answers, recorded("bjork-artists"))
    assert names(search(answers, "bjork"))["artists"][0] == "Björk"
    assert names(search(answers, "BJÖRK"))["artists"][0] == "Björk"
    assert names(search(answers, "björ"))["artists"][0] == "Björk"


def test_names_and_titles_rank_over_credits_and_an_exact_name_comes_first(saved):
    answers = saved()
    put(answers, recorded("bjork-artists"), recorded("portishead-discography"), STUDIO)
    #? Björk has a dozen spellings among her other names, which bm25's length weighting holds against her: the exact
    #? name is lifted to the top
    assert names(search(answers, "bjork"))["artists"][0] == "Björk"
    albums = names(search(answers, "portishead"))["albums"]
    assert albums[0] == "Portishead", "the album titled exactly so, first"
    titled = [title for title in albums if "portishead" in title.lower()]
    assert albums[: len(titled)] == titled, "titles naming Portishead before albums only credited to them"


def test_a_name_they_go_by_typed_exactly_is_lifted_too(saved):
    """"kanye west": Ye - who went by it - before a tribute band whose name only starts with it."""
    answers = saved()
    put(answers, ("artist/", {"query": "kanye west"}, {"artists": [
        {"id": "00000000-0000-4000-8000-0000000000t1", "name": "Kanye West Tribute Band"},
        {"id": "00000000-0000-4000-8000-0000000000e1", "name": "Ye", "aliases": [{"name": "Kanye West"}, {"name": "Yeezy"}, {"name": "Kanye Omari West"}]},
    ]}))
    assert names(search(answers, "kanye west"))["artists"] == ["Ye", "Kanye West Tribute Band"]


def test_a_title_weighs_over_a_credit(saved):
    """Neither named exactly as typed: the album with the words in its title before the one only credited to them."""
    answers = saved()
    put(answers, ("release-group/", {"query": "x"}, {"release-groups": [
        {"id": "00000000-0000-4000-8000-0000000000c1", "title": "Dummy", "artist-credit": [{"name": "Portishead", "artist": {"id": PORTISHEAD, "name": "Portishead"}}]},
        {"id": "00000000-0000-4000-8000-0000000000c2", "title": "Welcome to Portishead", "artist-credit": [{"name": "Somebody", "artist": {"id": "00000000-0000-4000-8000-00000000b0d1", "name": "Somebody"}}]},
    ]}))
    assert names(search(answers, "portishead"))["albums"] == ["Welcome to Portishead", "Dummy"]


def test_a_credit_read_off_a_release_never_replaces_the_albums_own(saved):
    """A song search's release carries its group with no credit: the release's credit only fills an album nothing better
    has credited - a newer song search never re-credits an album an album search said whose it is."""
    clock = Clock()
    answers = saved(clock=clock)
    put(answers, ("release-group/", {"query": "x"}, {"release-groups": [{"id": DUMMY, "title": "Dummy", "artist-credit": [{"name": "Portishead", "artist": {"id": PORTISHEAD, "name": "Portishead"}}]}]}))
    clock.now += 60
    put(answers, ("recording/", {"query": "y"}, {"recordings": [{"id": "00000000-0000-4000-8000-0000000000r1", "title": "Roads",
        "artist-credit": [{"name": "Portishead", "artist": {"id": PORTISHEAD, "name": "Portishead"}}],
        "releases": [{"id": "00000000-0000-4000-8000-0000000000p1", "title": "Dummy", "artist-credit": [{"name": "Various Artists", "artist": {"id": "89ad4ac3-39f7-470e-963a-56509c546377", "name": "Various Artists"}}],
                      "release-group": {"id": DUMMY, "title": "Dummy", "primary-type": "Album"}, "media": [{"track": [{"number": "8", "title": "Roads", "length": 1}]}]}]}]}))
    assert names(search(answers, "dummy portishead"))["albums"] == ["Dummy"]
    assert credit_name(search(answers, "dummy")["albums"]["release-groups"][0]["artist-credit"]) == "Portishead"
    #? ...and fills one nothing has credited
    put(answers, ("recording/", {"query": "z"}, {"recordings": [{"id": "00000000-0000-4000-8000-0000000000r2", "title": "Song",
        "releases": [{"id": "00000000-0000-4000-8000-0000000000p2", "title": "Comp", "artist-credit": [{"name": "Various Artists"}],
                      "release-group": {"id": "00000000-0000-4000-8000-0000000000g2", "title": "Comp", "primary-type": "Album", "secondary-types": ["Compilation"]},
                      "media": [{"track": [{"number": "1", "title": "Song", "length": 1}]}]}]}]}))
    assert credit_name(search(answers, "comp")["albums"]["release-groups"][0]["artist-credit"]) == "Various Artists"


@pytest.mark.parametrize("words", ['dummy OR "', "NEAR(dummy glory)", "title:dummy", "dummy*", "-dummy", "^dummy", "{title}: dummy", '"glory" AND box'])
def test_nothing_typed_is_read_as_full_text_syntax(saved, words):
    answers = saved()
    put(answers, recorded("dummy-pressings"))
    assert search(answers, words) is not None, "never an error"


def test_words_with_nothing_to_match_find_nothing(saved):
    answers = saved()
    put(answers, recorded("dummy-pressings"))
    assert saved_index.match_expression("& - !") is None
    assert names(search(answers, "& -")) == {"artists": [], "albums": [], "songs": []}
    assert saved_index.match_expression('glory "box') == '"glory" """box"*'


def test_a_search_is_bounded_to_the_apps_pages(saved):
    answers = saved()
    groups = [{"id": f"00000000-0000-4000-8000-{n:012d}", "title": f"Roads {n}", "primary-type": "Album"} for n in range(40)]
    put(answers, ("release-group/", {"query": "roads"}, {"release-groups": groups}))
    assert len(search(answers, "roads")["albums"]["release-groups"]) == saved_index.SAVED_ALBUMS == 12


# ------------------------------------------------------------------ kept in step with the cache


def test_a_refresh_replacing_an_answer_takes_what_only_it_mentioned(saved):
    answers = saved()
    first = ("release-group/", {"query": "x"}, {"release-groups": [{"id": DUMMY, "title": "Dummy"}, {"id": "00000000-0000-4000-8000-000000000001", "title": "Gone Since"}]})
    put(answers, first)
    assert names(search(answers, "gone"))["albums"] == ["Gone Since"]
    put(answers, ("release-group/", {"query": "x"}, {"release-groups": [{"id": DUMMY, "title": "Dummy"}]}))
    assert names(search(answers, "gone"))["albums"] == []
    assert names(search(answers, "dummy"))["albums"] == ["Dummy"]


def test_the_trim_drops_what_no_answer_mentions_and_only_that(saved):
    clock = Clock()
    answers = saved(max_bytes=1 << 20, clock=clock)
    put(answers, recorded("dummy-pressings"))
    clock.now += 1
    put(answers, ARTISTS)                                     # Portishead, by another answer too
    for n in range(160):                                      # then enough to trim the oldest away
        clock.now += 1
        asyncio.run(answers.get(ResponseCache.disk_key(*ARTISTS[:2])))   # the artist search used now and then
        noise = [{"id": f"00000000-0000-4000-8000-{n:06d}{m:06d}", "title": f"Filler {n} {m} " + "x" * 40} for m in range(60)]
        put(answers, ("release-group/", {"query": f"filler {n}"}, {"release-groups": noise}))
    with sqlite3.connect(answers.path()) as connection:
        kept = {json.loads(key)[0] for (key,) in connection.execute("SELECT key FROM answers")}
        count = connection.execute("SELECT COUNT(*) FROM answers").fetchone()[0]
    assert "release/" not in kept, "Dummy's pressings, used longest ago, trimmed away"
    assert count > 20, "the index's share counted as the answers go: trimmed back under the budget, not emptied"
    assert names(search(answers, "glory box"))["songs"] == [], "...and the songs only they mentioned went with them"
    with sqlite3.connect(answers.path()) as connection:
        things = sum(connection.execute(f"SELECT COUNT(*) FROM saved_{kind}").fetchone()[0] for kind in ("artists", "albums", "songs"))
        assert connection.execute("SELECT COUNT(*) FROM saved_words").fetchone()[0] == things, "their words gone with them"
    assert names(search(answers, "portishead"))["artists"] == ["Portishead"], "an artist another answer mentions stays"
    assert rows(answers.path(), "saved_releases") == 0


def test_the_index_counts_toward_the_budget(saved):
    answers = saved()
    put(answers, recorded("dummy-pressings"))
    with sqlite3.connect(answers.path()) as connection:
        stored = connection.execute("SELECT SUM(size) FROM answers").fetchone()[0]
        pages = connection.execute("PRAGMA page_count").fetchone()[0] - connection.execute("PRAGMA freelist_count").fetchone()[0]
        used = pages * connection.execute("PRAGMA page_size").fetchone()[0]
    assert used > stored + 20_000, "the file the budget measures holds the index's pages too"


def test_clear_empties_the_index_with_the_answers(saved):
    answers = saved()
    put(answers, recorded("dummy-pressings"), STUDIO, ARTISTS)
    asyncio.run(answers.clear())
    assert names(search(answers, "portishead")) == {"artists": [], "albums": [], "songs": []}
    for table in ("saved_artists", "saved_albums", "saved_songs", "saved_releases", "saved_mentions"):
        assert rows(answers.path(), table) == 0, table
    put(answers, STUDIO)
    assert names(search(answers, "third"))["albums"] == ["Third"], "and it fills again"


def test_zero_turns_saved_search_off(saved, tmp_path):
    answers = saved()
    put(answers, recorded("dummy-pressings"))
    off = saved(max_bytes=0, path=tmp_path / "musicbrainz-cache.db")
    assert search(off, "glory box") is None


def test_no_file_yet_is_nothing_to_search(saved):
    answers = saved()
    assert search(answers, "glory box") is None
    assert not Path(answers.path()).exists(), "a search never makes the file"


# ------------------------------------------------------------------ the answers already saved


def unindexed(path: Path, *found) -> None:
    """A file as 2.0.0-player.54 and .55 made it: answers, and no index."""
    answers = SavedAnswers(path=str(path), max_bytes=50 << 20, clock=Clock())
    put(answers, *found)
    asyncio.run(answers.close())
    with sqlite3.connect(path) as connection:
        for table in saved_index.INDEX_TABLES:
            connection.execute(f"DROP TABLE IF EXISTS {table}")
        connection.execute("DELETE FROM meta WHERE name LIKE 'index_%'")


def test_answers_saved_before_the_index_are_read_into_it_once_in_the_background(saved, tmp_path, caplog, monkeypatch):
    path = tmp_path / "musicbrainz-cache.db"
    fillers = [("release-group/", {"query": f"f{n}"}, {"release-groups": [{"id": f"00000000-0000-4000-8000-{n:012d}", "title": f"Filler {n}"}]}) for n in range(60)]
    unindexed(path, recorded("dummy-pressings"), *fillers)
    caplog.set_level("INFO")
    monkeypatch.setattr(musicbrainz_cache, "BACKFILL_ANSWERS", 7)        # in steps, as a big file is
    answers = saved(path=path)
    answers.warm()                                                       # the app's lifespan
    for _ in range(200):
        asyncio.run(answers.flush())
        with sqlite3.connect(path) as connection:
            at, to = (int(value) for (value,) in connection.execute(
                "SELECT value FROM meta WHERE name IN ('index_at', 'index_to') ORDER BY name"))
        if at >= to:
            break
    assert set(names(search(answers, "glory box"))["songs"]) == {"Glory Box"}
    assert names(search(answers, "filler 59"))["albums"] == ["Filler 59"]
    done = [record.getMessage() for record in caplog.records if "read into the saved-search index" in record.getMessage()]
    assert done == ["MusicBrainz's saved answers: 61 read into the saved-search index - Search finds what they hold under any words now"]
    #? once: opened again, nothing is read again
    asyncio.run(answers.reset())
    answers.warm()
    asyncio.run(answers.flush())
    assert len([record for record in caplog.records if "read into the saved-search index" in record.getMessage()]) == 1


def test_a_search_during_the_backfill_waits_for_one_step_at_most(saved, tmp_path, monkeypatch):
    path = tmp_path / "musicbrainz-cache.db"
    unindexed(path, recorded("dummy-pressings"), *[("release-group/", {"query": f"f{n}"}, {"release-groups": [{"id": f"00000000-0000-4000-8000-{n:012d}", "title": f"Filler {n}"}]}) for n in range(30)])
    monkeypatch.setattr(musicbrainz_cache, "BACKFILL_ANSWERS", 1)
    answers = saved(path=path)
    steps = []
    real = answers._backfill_step

    def step():
        steps.append(time.monotonic())
        real()

    monkeypatch.setattr(answers, "_backfill_step", step)
    progress = []
    real_search = saved_index.search

    def searching(connection, words):
        progress.append(tuple(int(value) for (value,) in connection.execute(
            "SELECT value FROM meta WHERE name IN ('index_at', 'index_to') ORDER BY name")))
        return real_search(connection, words)

    monkeypatch.setattr(saved_index, "search", searching)
    answers.warm()

    async def go():
        await asyncio.sleep(0)
        return await answers.search("filler")

    found = asyncio.run(go())
    assert found is not None, "answered, between two steps"
    asyncio.run(answers.flush())
    at, to = progress[0]
    assert at < to, "the search went between steps, not after them all"
    assert 1 < len(steps) < 31


def test_without_fts5_answers_are_saved_and_search_finds_nothing_said_once(saved, monkeypatch, caplog):
    real = saved_index.make_index

    def without(connection, drop=False):
        real(connection, drop)
        raise sqlite3.OperationalError("no such module: fts5")

    monkeypatch.setattr(saved_index, "make_index", without)
    caplog.set_level("INFO")
    answers = saved()
    put(answers, STUDIO, ARTISTS)
    assert rows(answers.path(), "answers") == 2, "answers saved as ever"
    assert search(answers, "third") is None
    said = [record.getMessage() for record in caplog.records if "FTS5" in record.getMessage()]
    assert len(said) == 1 and "Search won't find what is saved" in said[0]
    put(answers, recorded("bjork-artists"))
    assert len([record for record in caplog.records if "FTS5" in record.getMessage()]) == 1, "said once"


def test_a_slow_search_is_given_up(saved, monkeypatch):
    answers = saved()
    put(answers, STUDIO)
    monkeypatch.setattr(musicbrainz_cache, "READ_TIMEOUT_SECONDS", 0.05)
    hold = threading.Event()
    real = saved_index.search

    def slow(*args, **kwargs):
        hold.wait(2)
        return real(*args, **kwargs)

    monkeypatch.setattr(saved_index, "search", slow)
    started = time.monotonic()
    assert search(answers, "third") is None
    assert time.monotonic() - started < 1
    hold.set()


def test_a_search_runs_on_the_saved_answers_thread_never_the_event_loop(saved, monkeypatch):
    answers = saved()
    put(answers, STUDIO)
    where = []
    real = saved_index.search
    monkeypatch.setattr(saved_index, "search", lambda *args, **kwargs: (where.append(threading.current_thread().name), real(*args, **kwargs))[1])
    assert search(answers, "third") is not None
    assert where and where[0].startswith("musicbrainz-answers")


# ------------------------------------------------------------------ the route


class Disk:
    def __init__(self, answers):
        self.disk = answers


def client_for(answers) -> TestClient:
    app = FastAPI()
    app.include_router(search_musicbrainz.router, prefix="/search_musicbrainz")
    app.state.musicbrainz_client = type("Client", (), {"cache": Disk(answers)})()
    return TestClient(app)


def test_the_route_answers_in_the_shapes_the_app_already_draws(saved):
    """The same shapes as /artists, /fully_search and /songs - so Search draws a saved row with MusicBrainz's row."""
    answers = saved()
    put(answers, recorded("dummy-pressings"), STUDIO, ARTISTS, ROADS)
    with client_for(answers) as http:
        artists = http.get("/search_musicbrainz/saved", params={"words": "portishead"}).json()
        glory = http.get("/search_musicbrainz/saved", params={"words": "glory box"}).json()
        roads = http.get("/search_musicbrainz/saved", params={"words": "roads"}).json()
    assert artists["available"] is True
    match = artists["artists"]["matches"][0]
    assert set(match) == set(artist_match({"id": "x", "name": "x"}, "x")), "an /artists match, key for key"
    assert match["matched_as"] == "Portishead" and match["mbid"] == PORTISHEAD
    group = artists["albums"]["release-groups"][0]
    real = next(each for each in STUDIO[2]["release-groups"] if each["id"] == group["id"])
    assert set(group) <= set(real) | {"secondary-types"}, "a release group as a search answers it"
    assert {key: group[key] for key in ("id", "title", "primary-type", "first-release-date")} == {key: real.get(key, "") for key in ("id", "title", "primary-type", "first-release-date")}
    assert credit_name(group["artist-credit"]) == credit_name(real["artist-credit"])
    #? a recording as /songs answers it: what ui/src/lib/songs.ts groupSongs reads, every key of it
    recording = glory["songs"]["recordings"][0]
    assert {"id", "title", "length", "artist-credit", "releases"} <= set(recording)
    release = recording["releases"][0]
    assert {"id", "title", "status", "date", "country", "artist-credit", "release-group", "media"} <= set(release)
    assert {"id", "title", "primary-type", "secondary-types"} <= set(release["release-group"])
    assert {"number", "title", "length"} <= set(release["media"][0]["track"][0])
    road = next(each for each in roads["songs"]["recordings"] if each["id"] in {one["id"] for one in ROADS[2]["recordings"]})
    original = next(each for each in ROADS[2]["recordings"] if each["id"] == road["id"])
    assert {each["release-group"]["id"] for each in road["releases"]} <= {each["release-group"]["id"] for each in original["releases"]}
    assert road["title"] == original["title"] and road["length"] == original["length"]


def test_the_route_says_when_nothing_could_be_searched(saved, tmp_path):
    with client_for(None) as http:
        answer = http.get("/search_musicbrainz/saved", params={"words": "dummy"}).json()
    assert answer == {"artists": {"matches": [], "count": 0}, "albums": {"release-groups": [], "count": 0},
                      "songs": {"recordings": [], "count": 0}, "credited": {"release-groups": [], "count": 0}, "available": False}
    with client_for(saved(max_bytes=0)) as http:
        assert http.get("/search_musicbrainz/saved", params={"words": "dummy"}).json()["available"] is False


@pytest.mark.parametrize("words, status", [("", 422), ("x" * 201, 422), ("   ", 200), ("x" * 200, 200)])
def test_the_routes_bounds(saved, words, status):
    answers = saved()
    put(answers, STUDIO)
    with client_for(answers) as http:
        answer = http.get("/search_musicbrainz/saved", params={"words": words})
    assert answer.status_code == status
    if status == 200 and not words.strip():
        assert answer.json()["available"] is False


def test_the_route_is_bounded_to_the_box_as_the_app_types_it():
    assert search_musicbrainz.SAVED_SEARCH_WORDS_MAX == search_musicbrainz.ARTIST_SEARCH_NAME_MAX == 200


def test_the_pages_are_the_apps_own():
    """The saved kinds are never longer than the MusicBrainz answers drawn under them: the app's own page sizes."""
    ui = (Path(__file__).resolve().parent.parent / "ui" / "src")
    assert f"MUSICBRAINZ_LIMIT = {saved_index.SAVED_ALBUMS}" in (ui / "app" / "Search.tsx").read_text()
    assert f"SONG_SEARCH_LIMIT = {saved_index.SAVED_SONGS}" in (ui / "lib" / "songs.ts").read_text()
    #? the artist reading draws MusicBrainz's page of their saved albums, chosen from the route's `credited`
    assert f"SAVED_ARTIST_ALBUMS = {saved_index.SAVED_ALBUMS}" in (ui / "lib" / "searchList.ts").read_text()
    assert saved_index.SAVED_CREDITED >= saved_index.SAVED_ALBUMS
    assert saved_index.SAVED_ARTISTS == search_musicbrainz.ARTIST_SEARCH_LIMIT


def test_songs_of_one_title_the_most_released_first(saved):
    """A song search's covers are saved too: "glory box" means Portishead's, on many pressings, before a cover on one."""
    answers = saved()
    cover = ("recording/", {"query": "glory box"}, {"recordings": [{"id": "00000000-0000-4000-8000-0000000c0ve1", "title": "Glory Box",
             "artist-credit": [{"name": "Somebody", "artist": {"id": "00000000-0000-4000-8000-00000000b0d1", "name": "Somebody"}}],
             "releases": [{"id": "00000000-0000-4000-8000-0000000c0ve2", "title": "Covers", "release-group": {"id": "00000000-0000-4000-8000-0000000c0ve3", "title": "Covers", "primary-type": "Album"},
                           "media": [{"track": [{"number": "1", "title": "Glory Box", "length": 1}]}]}]}]})
    put(answers, cover, recorded("dummy-pressings"))
    found = search(answers, "glory box")["songs"]["recordings"]
    assert found[0]["artist-credit"][0]["artist"]["id"] == PORTISHEAD and len(found[0]["releases"]) == 2
    assert [each["artist-credit"][0]["name"] for each in found].index("Somebody") > 0
    assert [each["title"] for each in search(answers, "glory b")["songs"]["recordings"]][-1] == "Glory Box"


# ------------------------------------------------------------------ after review (2.0.0-player.56's fixes)


def uid(n: int, kind: str = "0") -> str:
    """A made-up MusicBrainz id: `kind` (one hex digit) keeps artists, albums, pressings, tracks and songs apart."""
    return f"00000000-0000-4000-800{kind}-{n:012d}"


BAND = [{"name": "Band", "joinphrase": "", "artist": {"id": uid(1, "a"), "name": "Band"}}]


def album_page(group: str, recording: str, pressings: int, title: str = "Tune", first: int = 0, track_title: str | None = None):
    """An album's pressings with their tracklists, as the app asks for them: `pressings` of them, each with `recording`
    as track 1."""
    return ("release/", {"release-group": group, "inc": "media+recordings+release-groups", "fmt": "json", "limit": 100, "offset": 0},
            {"releases": [{"id": uid(first + n, "1"), "title": "Album", "status": "Official", "date": f"{2000 + n % 20}-01-{1 + n // 20:02d}",
                           "artist-credit": BAND, "release-group": {"id": group, "title": "Album", "primary-type": "Album", "artist-credit": BAND},
                           "media": [{"position": 1, "tracks": [{"id": uid(first + n, "2"), "number": "1", "title": track_title or title, "length": 1000,
                                                                 "recording": {"id": recording, "title": title, "length": 1000}}]}]}
                          for n in range(pressings)]})


def song_search(words: str, recording: str, release: str, group: str, title: str = "Tune", credit=BAND, disambiguation: str = ""):
    """A song search finding `recording` on one pressing."""
    return ("recording/", {"query": f'recording:"{words}"', "fmt": "json", "limit": 25}, {"recordings": [
        {"id": recording, "title": title, "length": 1000, "disambiguation": disambiguation, "artist-credit": credit,
         "releases": [{"id": release, "title": "Single", "status": "Official", "date": "1999", "release-group": {"id": group, "title": "Single", "primary-type": "Single"},
                       "media": [{"position": 1, "track": [{"number": "1", "title": title, "length": 1000}]}]}]}]})


def put_at(answers: SavedAnswers, *found: tuple[tuple, float]) -> None:
    """Answers saved as fetched at given times - the backfill reads week-old ones after today's."""
    for (endpoint, params, payload), fetched_at in found:
        answers.put(ResponseCache.disk_key(endpoint, params), payload, fetched_at=fetched_at)
    asyncio.run(answers.flush())


@pytest.mark.parametrize("song_first", [True, False])
def test_a_songs_pressings_are_every_answers_whichever_is_read_in_first(saved, song_first):
    """The review's catch: a song search (newer) then an album page read in after it (older, as the backfill reads it)
    kept only the song search's pressing. Both answers' pressings, either way round."""
    song, album = uid(1, "5"), uid(1, "6")
    page, single = album_page(album, song, 3), song_search("tune", song, uid(99, "1"), uid(2, "6"))
    order = [(single, 1.5e9), (page, 1e9)] if song_first else [(page, 1e9), (single, 1.5e9)]
    answers = saved()
    put_at(answers, *order)
    [found] = search(answers, "tune")["songs"]["recordings"]
    assert len(found["releases"]) == 4


def test_songs_are_ordered_by_the_pressings_still_saved_never_ones_trimmed_away(saved):
    """The review's catch: a song's pressings kept the numbers of pressings gone with their answer, so it still counted
    seventeen though it showed one - and came before a cover genuinely on two."""
    original, cover = uid(1, "5"), uid(2, "5")
    page = album_page(uid(1, "6"), original, 17)
    answers = saved()
    put(answers, page, song_search("tune", original, uid(90, "1"), uid(2, "6")),
        ("recording/", {"query": "tune covers"}, {"recordings": [{"id": cover, "title": "Tune", "artist-credit": [{"name": "Other", "artist": {"id": uid(2, "a"), "name": "Other"}}],
                                                                   "releases": [{"id": uid(80 + n, "1"), "title": f"Covers {n}", "release-group": {"id": uid(80 + n, "6"), "title": f"Covers {n}", "primary-type": "Album"},
                                                                                 "media": [{"track": [{"number": "1", "title": "Tune", "length": 1}]}]} for n in range(2)]}]}))
    assert [each["id"] for each in search(answers, "tune")["songs"]["recordings"]] == [original, cover]
    #? the album page refreshed to nothing: its seventeen pressings go, the song search's one stays
    put(answers, (page[0], page[1], {"releases": []}))
    found = search(answers, "tune")["songs"]["recordings"]
    assert [(each["id"], len(each["releases"])) for each in found] == [(cover, 2), (original, 1)]


def test_a_search_is_bounded_in_artists_and_songs_too(saved):
    answers = saved()
    put(answers, ("artist/", {"query": "band"}, {"artists": [{"id": uid(n, "a"), "name": f"Band {n}"} for n in range(30)]}),
        ("recording/", {"query": "tune"}, {"recordings": [
            {"id": uid(n, "5"), "title": f"Tune {n}", "releases": [{"id": uid(n, "1"), "title": "S", "release-group": {"id": uid(n, "6"), "title": "S", "primary-type": "Single"},
                                                                  "media": [{"track": [{"number": "1", "title": f"Tune {n}", "length": 1}]}]}]} for n in range(40)]}))
    found = search(answers, "band tune")
    assert found["artists"]["count"] == 0
    assert len(search(answers, "band")["artists"]["matches"]) == saved_index.SAVED_ARTISTS == 10
    assert len(search(answers, "tune")["songs"]["recordings"]) == saved_index.SAVED_SONGS == 25


def test_a_songs_pressings_are_oldest_first_and_at_most_a_hundred(saved):
    song = uid(1, "5")
    answers = saved()
    second = album_page(uid(1, "6"), song, 30, first=100)
    #? the browse's second page, its pressings the oldest
    put(answers, album_page(uid(1, "6"), song, 100), (second[0], {**second[1], "offset": 100},
        {"releases": [{**release, "date": "1990"} for release in second[2]["releases"]]}))
    [found] = search(answers, "tune")["songs"]["recordings"]
    dates = [release["date"] for release in found["releases"]]
    assert len(dates) == saved_index.SAVED_PRESSINGS_PER_SONG == 100
    assert dates == sorted(dates) and dates[0] == "1990", "the oldest first - and the cap keeps those"


def test_a_track_titled_otherwise_than_its_song_says_so(saved):
    answers = saved()
    put(answers, album_page(uid(1, "6"), uid(1, "5"), 1, title="Tune", track_title="Tune (album version)"))
    [found] = search(answers, "tune")["songs"]["recordings"]
    assert found["title"] == "Tune" and found["releases"][0]["media"][0]["track"][0]["title"] == "Tune (album version)"


def test_a_pressing_titled_as_its_album_keeps_no_title_of_its_own(saved):
    answers = saved()
    page = album_page(uid(1, "6"), uid(1, "5"), 2)
    page[2]["releases"][1]["title"] = "Album (Deluxe)"
    put(answers, page)
    with sqlite3.connect(answers.path()) as connection:
        titles = sorted(connection.execute("SELECT COALESCE(title, '-') FROM saved_releases").fetchall())
    assert titles == [("-",), ("Album (Deluxe)",)]
    found = search(answers, "tune")["songs"]["recordings"][0]["releases"]
    assert sorted(release["title"] for release in found) == ["Album", "Album (Deluxe)"]


def test_the_route_answers_disambiguations(saved):
    answers = saved()
    put(answers, ("artist/", {"query": "band"}, {"artists": [{"id": uid(1, "a"), "name": "Band", "disambiguation": "the Bristol one"}]}),
        song_search("tune", uid(1, "5"), uid(1, "1"), uid(1, "6"), disambiguation="live, 1998"))
    with client_for(answers) as http:
        band = http.get("/search_musicbrainz/saved", params={"words": "band"}).json()
        tune = http.get("/search_musicbrainz/saved", params={"words": "tune"}).json()
    assert band["artists"]["matches"][0]["disambiguation"] == "the Bristol one"
    assert tune["songs"]["recordings"][0]["disambiguation"] == "live, 1998"


def test_credit_name_trims_a_trailing_join_phrase():
    assert credit_name([{"name": "Band", "joinphrase": " "}]) == "Band"
    assert credit_name([{"name": " Band"}]) == "Band"


# ------------------------------------------------------------------ after review: kept in step, whatever happens


def test_the_settings_look_at_a_file_without_an_index_writes_nothing_of_one(saved, tmp_path):
    path = tmp_path / "musicbrainz-cache.db"
    unindexed(path, STUDIO)
    answers = saved(path=path)
    assert asyncio.run(answers.stats())["answers"] == 1
    with sqlite3.connect(path) as connection:
        tables = {name for (name,) in connection.execute("SELECT name FROM sqlite_master")}
        meta = [name for (name,) in connection.execute("SELECT name FROM meta WHERE name LIKE 'index_%'")]
    assert not tables & set(saved_index.INDEX_TABLES) and meta == []


def test_an_unreadable_answer_dropped_takes_its_things_from_the_index(saved):
    """The review's catch: a read that finds an answer it can't unpack drops it - and left what only it mentioned
    found by Search ever after."""
    answers = saved()
    put(answers, recorded("dummy-pressings"), STUDIO)
    key = ResponseCache.disk_key(*recorded("dummy-pressings")[:2])
    with sqlite3.connect(answers.path()) as connection:
        connection.execute("UPDATE answers SET body = ? WHERE key = ?", (b"not zlib", key))
    assert asyncio.run(answers.get(key)) is None
    assert names(search(answers, "glory box"))["songs"] == []
    assert names(search(answers, "third"))["albums"] == ["Third"], "only its own"


def test_stopping_during_the_backfill_never_sets_the_file_aside(saved, tmp_path, monkeypatch):
    """The review's catch: deadwax stopped while the answers already saved were being read in (a redeploy, the first
    start after the upgrade). The step queued behind the close reopened the file, queued the next on a NEW worker -
    which used the old thread's connection, and SQLite's "created in a thread" error was taken for a broken file: the
    whole file set aside. Now nothing runs after the close, the file is kept, and the next start goes on from there."""
    path = tmp_path / "musicbrainz-cache.db"
    fillers = [("release-group/", {"query": f"f{n}"}, {"release-groups": [{"id": uid(n, "6"), "title": f"Filler {n}"}]}) for n in range(300)]
    unindexed(path, *fillers)
    monkeypatch.setattr(musicbrainz_cache, "BACKFILL_ANSWERS", 2)
    answers = SavedAnswers(path=str(path), max_bytes=50 << 20, clock=Clock())

    async def go():
        answers.warm()
        await asyncio.sleep(0.02)
        await answers.close()

    asyncio.run(go())
    time.sleep(0.2)
    assert [each.name for each in tmp_path.iterdir()] == ["musicbrainz-cache.db"], "nothing set aside"
    assert not [thread for thread in threading.enumerate() if thread.name.startswith("musicbrainz-answers") and thread.is_alive()]
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM answers").fetchone()[0] == 300
        at, to = (int(value) for (value,) in connection.execute(
            "SELECT value FROM meta WHERE name IN ('index_at', 'index_to') ORDER BY name"))
    assert 0 < at < to, "stopped part way"
    again = saved(path=path)
    again.warm()
    for _ in range(400):
        asyncio.run(again.flush())
        if names(search(again, "filler 299"))["albums"] == ["Filler 299"]:
            break
    assert names(search(again, "filler 0"))["albums"] == ["Filler 0"], "...and the next start goes on from there"


def test_a_connection_misused_is_never_taken_for_a_broken_file(saved):
    answers = saved()
    put(answers, STUDIO)

    def misused(connection):
        raise sqlite3.ProgrammingError("SQLite objects created in a thread can only be used in that same thread")

    assert asyncio.run(answers._run(answers._with_file, False, misused, "default")) == "default"
    assert sorted(each.name for each in Path(answers.path()).parent.iterdir()) == ["musicbrainz-cache.db"]
    assert names(search(answers, "third"))["albums"] == ["Third"], "opened afresh, everything still there"


def test_an_older_deadwax_using_the_file_since_has_it_read_in_afresh(saved, tmp_path, caplog):
    """The review's catch: deadwax rolled back to 2.0.0-player.55 for a while, then forward. .55 cleared the answers and
    saved others without a word to the index - which went on finding what was gone, and never what was new."""
    path = tmp_path / "musicbrainz-cache.db"
    answers = saved(path=path)
    #? (second review) Dummy's answer NOT the first saved: .55's one answer after its Clear takes rowid 1 again, and
    #? reading it in would have taken a stale index's rowid-1 mentions away by coincidence - Dummy's are rowid 2's
    put(answers, ("release-group/", {"query": "first"}, {"release-groups": [{"id": uid(1, "6"), "title": "Somewhere First"}]}),
        recorded("dummy-pressings"))
    asyncio.run(answers.close())
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT rowid FROM answers WHERE key = ?",
                                  (ResponseCache.disk_key(*recorded("dummy-pressings")[:2]),)).fetchone()[0] == 2
    #? .55's Clear, then an answer it saved
    with sqlite3.connect(path, isolation_level=None) as connection:
        connection.execute("DELETE FROM answers")
        connection.execute("VACUUM")
        endpoint, params, payload = STUDIO
        connection.execute("INSERT INTO answers (key, body, size, fetched_at, used_at) VALUES (?, ?, ?, ?, ?)",
                           (ResponseCache.disk_key(endpoint, params), musicbrainz_cache.pack(payload), 1, 1e9, 1e9))
    caplog.set_level("INFO")
    back = saved(path=path)
    back.warm()
    for _ in range(20):
        asyncio.run(back.flush())
    assert names(search(back, "glory box"))["songs"] == [], "what .55 cleared is gone"
    assert names(search(back, "somewhere first"))["albums"] == []
    assert names(search(back, "third"))["albums"] == ["Third"], "what .55 saved is found"
    assert any("changed while the saved-search index wasn't kept" in record.getMessage() for record in caplog.records)


@pytest.mark.parametrize("trigger", saved_index.TRIGGER_NAMES)
def test_a_trigger_missing_has_the_index_made_afresh(saved, tmp_path, caplog, trigger):
    """(second review) Without one of its triggers the index can't know what a change it didn't make did - a file of
    this version's builds before the triggers, say: made afresh and read in again, as for the stale mark."""
    path = tmp_path / "musicbrainz-cache.db"
    answers = saved(path=path)
    put(answers, recorded("dummy-pressings"), STUDIO)
    asyncio.run(answers.close())
    with sqlite3.connect(path, isolation_level=None) as connection:
        connection.execute(f"DROP TRIGGER {trigger}")
        #? ...and a change made without it: Dummy's answer gone, unmarked
        connection.execute("DELETE FROM answers WHERE key = ?", (ResponseCache.disk_key(*recorded("dummy-pressings")[:2]),))
        connection.execute("DELETE FROM meta WHERE name = ?", (saved_index.STALE,))
    caplog.set_level("INFO")
    back = saved(path=path)
    back.warm()
    for _ in range(20):
        asyncio.run(back.flush())
    assert names(search(back, "glory box"))["songs"] == [], "what went without the index told is gone"
    assert names(search(back, "third"))["albums"] == ["Third"]
    assert any("changed while the saved-search index wasn't kept" in record.getMessage() for record in caplog.records)
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND name = ?", (trigger,)).fetchone()[0] == 1, \
            "made again"


def test_the_index_is_made_afresh_only_when_the_answers_changed_without_it(saved, tmp_path, caplog):
    path = tmp_path / "musicbrainz-cache.db"
    answers = saved(path=path, max_bytes=1 << 20)
    put(answers, recorded("dummy-pressings"), STUDIO)
    asyncio.run(answers.get(ResponseCache.disk_key(*STUDIO[:2])))
    #? words that don't compress (the answers are stored zlib-packed): enough to go past the budget, so the trim runs
    for n in range(60):
        put(answers, ("release-group/", {"query": f"filler {n}"}, {"release-groups": [
            {"id": uid(n * 100 + m, "6"), "title": f"Filler {n} {m} " + hashlib.sha256(f"{n} {m}".encode()).hexdigest()} for m in range(60)]}))
    asyncio.run(answers.close())
    caplog.set_level("INFO")
    rebuilt = lambda: any("changed while the saved-search index wasn't kept" in record.getMessage() for record in caplog.records)  # noqa: E731
    #? (second review) the trim on its own, before any Clear (which takes the mark off whatever was left): checked
    #? across a restart - a trim leaving the mark had every restart after it read the whole index in again
    with sqlite3.connect(path) as connection:
        assert connection.execute("SELECT COUNT(*) FROM answers").fetchone()[0] < 62, "(trimmed)"
        assert connection.execute("SELECT 1 FROM meta WHERE name = ?", (saved_index.STALE,)).fetchone() is None, "the trim kept it in step"
    trimmed = saved(path=path, max_bytes=1 << 20)
    assert names(search(trimmed, "filler 59 0"))["albums"][0].startswith("Filler 59 0 "), "the newest kept, and found"
    assert not rebuilt(), "saves, refreshes and trims keep it in step"
    asyncio.run(trimmed.clear())
    put(trimmed, STUDIO)
    asyncio.run(trimmed.close())
    again = saved(path=path, max_bytes=1 << 20)
    assert names(search(again, "third"))["albums"] == ["Third"]
    assert not rebuilt(), "...and Clear"


def test_a_read_only_file_without_an_index_is_still_read(saved, tmp_path, caplog):
    """The review's catch: a file .55 made, that can't be written (a read-only mount): making the index failed, and the
    file was closed for it - every saved answer .55 still read was lost. Now it is read as before, Search finds nothing
    saved (said once), and making the index is tried again later."""
    path = tmp_path / "musicbrainz-cache.db"
    unindexed(path, STUDIO)
    path.chmod(0o444)
    try:
        caplog.set_level("INFO")
        answers = saved(path=path)
        found = asyncio.run(answers.get(ResponseCache.disk_key(*STUDIO[:2])))
        assert found is not None and found[0] == STUDIO[2]
        assert search(answers, "third") is None
        assert asyncio.run(answers.get(ResponseCache.disk_key(*STUDIO[:2]))) is not None
        said = [record.getMessage() for record in caplog.records if "couldn't make the saved-search index" in record.getMessage()]
        assert len(said) == 1
        #? writable again: made, after the retry minute
        path.chmod(0o644)
        answers._index_failed_at -= musicbrainz_cache.RETRY_OPEN_SECONDS + 1
        asyncio.run(answers.get(ResponseCache.disk_key(*STUDIO[:2])))
        for _ in range(5):
            asyncio.run(answers.flush())
        assert names(search(answers, "third"))["albums"] == ["Third"]
    finally:
        path.chmod(0o644)


def test_each_backfill_says_how_many_it_read_itself(saved, tmp_path, caplog):
    path = tmp_path / "musicbrainz-cache.db"
    unindexed(path, STUDIO, ARTISTS)
    caplog.set_level("INFO")
    answers = saved(path=path)
    answers.warm()
    for _ in range(5):
        asyncio.run(answers.flush())
    asyncio.run(answers.close())
    with sqlite3.connect(path) as connection:
        for table in saved_index.INDEX_TABLES:
            connection.execute(f"DROP TABLE IF EXISTS {table}")
        connection.execute("DELETE FROM meta WHERE name LIKE 'index_%'")
        connection.execute("DELETE FROM answers WHERE key = ?", (ResponseCache.disk_key(*ARTISTS[:2]),))
    answers.warm()
    for _ in range(5):
        asyncio.run(answers.flush())
    said = [record.getMessage().split(":")[1].split(" read")[0].strip() for record in caplog.records
            if "read into the saved-search index" in record.getMessage()]
    assert said == ["2", "1"]


def test_the_trim_merges_the_full_text_tables_deleted_entries(saved):
    clock = Clock()
    answers = saved(max_bytes=1 << 20, clock=clock)
    put(answers, STUDIO)
    statements = []
    asyncio.run(answers._run(lambda: answers._connection.set_trace_callback(
        lambda statement: None if statement.startswith("--") else statements.append(statement))))
    for n in range(200):
        clock.now += 1
        put(answers, ("release-group/", {"query": f"filler {n}"}, {"release-groups": [{"id": uid(n * 100 + m, "6"), "title": f"Filler {n} {m} " + "x" * 40} for m in range(60)]}))
    trims = [index for index, statement in enumerate(statements) if statement.startswith("DELETE FROM answers WHERE key")]
    assert trims, "trimmed"
    assert any("'merge'" in statement for statement in statements[trims[0]:])


def test_the_albums_credited_to_the_words_are_answered_whatever_their_titles(saved):
    """The review's catch: "metallica" read as the artist you have kept only albums CREDITED to them - from the twelve
    bm25 put forward, which titles naming Metallica filled first, so a whole saved discography came down to one album.
    `credited` is chosen from all of theirs, in the studio order the app reads an artist's albums in."""
    answers = saved()
    band = [{"name": "Metallica", "joinphrase": "", "artist": {"id": uid(1, "a"), "name": "Metallica"}}]
    other = [{"name": "Somebody", "joinphrase": "", "artist": {"id": uid(2, "a"), "name": "Somebody"}}]
    titled = [{"id": uid(n, "6"), "title": f"A Tribute to Metallica {n}", "primary-type": "Album", "first-release-date": "2005", "artist-credit": other} for n in range(30)]
    theirs = [{"id": uid(100 + n, "6"), "title": title, "primary-type": kind, "secondary-types": secondary, "first-release-date": date, "artist-credit": band}
              for n, (title, kind, secondary, date) in enumerate([
                  ("Live Shit", "Album", ["Live"], "1993"), ("Kill 'Em All", "Album", [], "1983"), ("Garage Days", "EP", [], "1987"),
                  ("Master of Puppets", "Album", [], "1986"), ("Metallica", "Album", [], "1991"), ("Untitled", "Album", [], "")])]
    put(answers, ("release-group/", {"query": "tributes"}, {"release-groups": titled}),
        ("release-group/", {"artist": uid(1, "a"), "offset": 0}, {"release-groups": theirs}),
        #? credited to Metallica AND somebody: their words, but not exactly theirs
        ("release-group/", {"query": "and friends"}, {"release-groups": [{"id": uid(200, "6"), "title": "Jam", "primary-type": "Album",
                                                                         "artist-credit": [{**band[0], "joinphrase": " & "}, *other]}]}))
    found = search(answers, "metallica")
    assert len(found["albums"]["release-groups"]) == 12 and "Kill 'Em All" not in names(found)["albums"], "(the twelve: titles first)"
    assert [group["title"] for group in found["credited"]["release-groups"]] == [
        "Kill 'Em All", "Master of Puppets", "Metallica", "Untitled", "Live Shit", "Garage Days"], "theirs alone, in studio order"
    assert search(answers, "METALLICA")["credited"]["count"] == 6 and search(answers, "metal")["credited"]["count"] == 0, "the words exactly"


def test_the_albums_credited_are_fifty_at_most_the_earliest_kept(saved):
    """(second review) `credited` is SAVED_CREDITED (50) at most, chosen after the studio order: the earliest kept,
    whatever order they were saved in."""
    answers = saved()
    band = [{"name": "Metallica", "joinphrase": "", "artist": {"id": uid(1, "a"), "name": "Metallica"}}]
    theirs = [{"id": uid(n, "6"), "title": f"Record {n}", "primary-type": "Album", "first-release-date": str(1950 + n), "artist-credit": band}
              for n in reversed(range(60))]
    put(answers, ("release-group/", {"artist": uid(1, "a"), "offset": 0}, {"release-groups": theirs}))
    found = search(answers, "metallica")["credited"]
    assert saved_index.SAVED_CREDITED == 50
    assert found["count"] == 50 and [group["title"] for group in found["release-groups"]] == [f"Record {n}" for n in range(50)]


@pytest.mark.parametrize("name, key", [("Björk", "bjork"), ("The Beatles", "beatles"), ("Simon & Garfunkel", "simon and garfunkel"),
                                       ("Sigur Rós (band)", "sigur ros"), ("AC/DC", "ac dc"), ("Guns N\u2019 Roses", "guns n roses"), ("  ", "")])
def test_name_key_is_the_apps_way_of_comparing_a_name(name, key):
    """ui/src/lib/owned.ts foldName()'s twin (ui/test/searchList.sim.cjs folds the same names to the same keys)."""
    assert saved_index.name_key(name) == key


def test_an_older_deadwaxs_changes_are_read_in_even_when_the_trim_on_opening_runs_first(saved, tmp_path):
    """The trim on opening runs before the index is made sure of, and keeps it in step as it drops answers - but never
    takes off the mark an older deadwax's changes left, which only a fresh index does: what .55 saved is still read in."""
    import os
    path = tmp_path / "musicbrainz-cache.db"
    answers = saved(path=path)
    put(answers, recorded("dummy-pressings"))
    asyncio.run(answers.close())
    with sqlite3.connect(path) as connection:
        for n in range(40):
            key = ResponseCache.disk_key("release-group/", {"query": f"noise {n}"})
            connection.execute("INSERT INTO answers (key, body, size, fetched_at, used_at) VALUES (?, ?, ?, ?, ?)",
                               (key, musicbrainz_cache.pack({"noise": os.urandom(20 << 10).hex()}), 40_000, 1e9, 1e9 + n))
        endpoint, params, payload = STUDIO
        connection.execute("INSERT INTO answers (key, body, size, fetched_at, used_at) VALUES (?, ?, ?, ?, ?)",
                           (ResponseCache.disk_key(endpoint, params), musicbrainz_cache.pack(payload), 1, 2e9, 2e9))
    back = saved(path=path, max_bytes=512 << 10)
    back.warm()
    for _ in range(20):
        asyncio.run(back.flush())
    assert rows(path, "answers") < 42, "trimmed on opening"
    assert names(search(back, "third"))["albums"] == ["Third"]
