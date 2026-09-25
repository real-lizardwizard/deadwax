"""
Lyrics from LRCLIB, written as a .lrc beside each track.

The sixth writer to the user's filesystem. Like the others, most of what matters is what it
refuses: a path outside the library, a filename that isn't one of the album's tracks, and a
.lrc that is already there. The rest pins the two distinctions the interface depends on -
"LRCLIB has nothing" is not "LRCLIB failed", and a search result is only this track if its
duration says so.
"""

import asyncio
from types import SimpleNamespace

import httpx
import pytest
from fastapi import HTTPException

from src.api.lrclib_endpoint import BASE_URL, LrclibClient
from src.config import Config
from src.library import read_album_dir, summarize_for_deletion
from src.lyrics import (LyricsUnavailable, choose_result, execute_lyrics, fetch_album_lyrics,
                        lookup_from_tags, lyrics_filename, parse_lrc, plan_lyrics,
                        read_track_lyrics, render_lyrics)
from tests.test_retag import seed, write_flac

ALBUM = "Tame Impala/The Slow Rush (2020)"
NAMES = ["01 - One More Year.flac", "02 - Instant Destiny.flac"]
SYNCED = "[00:12.50] Do you remember\n[00:15.00] We were young\n"


class FakeLrclib:
    """Answers from a table keyed on title; a title mapped to an exception raises it."""

    def __init__(self, answers):
        self.answers = answers
        self.asked = []

    async def find(self, lookup):
        self.asked.append(lookup)
        answer = self.answers.get(lookup["title"])
        if isinstance(answer, Exception):
            raise answer
        return answer


def run(coro):
    return asyncio.run(coro)


# ------------------------------------------------------------------ reading LRC


def test_synced_lines_carry_their_time_in_seconds():
    lines = parse_lrc("[00:12.50] Do you remember\n[01:02.345]We were young")
    assert lines == [{"time": 12.5, "text": "Do you remember"},
                     {"time": 62.345, "text": "We were young"}]


def test_a_chorus_written_once_with_several_timestamps_becomes_a_line_each_in_order():
    lines = parse_lrc("[00:30.00][01:30.00] Chorus\n[01:00.00] Verse")
    assert [(line["time"], line["text"]) for line in lines] == [
        (30.0, "Chorus"), (60.0, "Verse"), (90.0, "Chorus")]


def test_header_tags_are_not_lyrics():
    lines = parse_lrc("[ar:Portishead]\n[ti:Roads]\n[offset:+100]\n[00:50.37] Ohh, can't anybody see")
    assert [line["text"] for line in lines] == ["Ohh, can't anybody see"]


def test_plain_text_is_every_line_with_no_time_and_blank_ends_trimmed():
    lines = parse_lrc("\n\nFirst line\n\nSecond line\n\n")
    assert lines == [{"time": None, "text": "First line"}, {"time": None, "text": ""},
                     {"time": None, "text": "Second line"}]


# ------------------------------------------------------------------ what LRCLIB is asked


def test_the_track_artist_is_tried_before_the_album_artist():
    lookup = lookup_from_tags({"title": "Wish You Were Here", "artist": "Pink Floyd with Stéphane Grappelli",
                               "albumartist": "Pink Floyd", "album": "Wish You Were Here"}, 374.2)
    assert lookup["artists"] == ["Pink Floyd with Stéphane Grappelli", "Pink Floyd"]
    assert lookup["duration"] == 374.2


def test_a_file_with_no_title_or_no_artist_cannot_be_looked_up():
    assert lookup_from_tags({"artist": "Portishead"}, 300) is None
    assert lookup_from_tags({"title": "Roads"}, 300) is None


LOOKUP = {"title": "Roads", "artists": ["Portishead"], "album": "Dummy", "duration": 305.0}


def result(**overrides):
    return {"trackName": "Roads", "artistName": "Portishead", "albumName": "Dummy",
            "duration": 306.0, "syncedLyrics": SYNCED, "plainLyrics": "Do you remember",
            "instrumental": False, **overrides}


def test_a_search_result_of_another_length_is_a_different_recording():
    """A live version or an extended mix has the same name and can have different words."""
    assert choose_result([result(duration=400.0)], LOOKUP) is None
    assert not choose_result([result(duration=303.5)], LOOKUP).get("words_only")


def test_a_slightly_different_length_gives_the_words_but_never_the_timings():
    """
    A vinyl pressing runs a few seconds long - Dummy's 2014 "Sour Times" is 245s where LRCLIB's
    copies are 247-254s. Same words; timings that drift further out with every line.
    """
    near = choose_result([result(duration=317.0), result(duration=330.0)], LOOKUP)
    assert near["words_only"] and near["duration"] == 317.0
    assert render_lyrics(near) == ("Do you remember\n", "plain")


def test_words_only_with_no_plain_copy_strips_the_timings_itself():
    near = choose_result([result(duration=317.0, plainLyrics=None)], LOOKUP)
    assert render_lyrics(near) == ("Do you remember\nWe were young\n", "plain")


def test_a_search_result_for_another_song_is_never_taken():
    assert choose_result([result(trackName="Roads (Live at Roseland)")], LOOKUP) is None


def test_among_matches_the_album_then_synced_lyrics_win():
    single = result(albumName="Glory Box", syncedLyrics="[00:01.00] single")
    plain = result(syncedLyrics=None)
    synced = result()
    assert choose_result([single, plain, synced], LOOKUP) is synced
    assert choose_result([single, plain], LOOKUP) is plain


def test_with_no_duration_known_the_name_alone_decides():
    assert choose_result([result(duration=999)], {**LOOKUP, "duration": 0}) is not None


def test_synced_lyrics_are_preferred_and_written_untouched():
    text, kind = render_lyrics(result())
    assert (text, kind) == (SYNCED, "synced")


def test_plain_lyrics_are_written_when_there_are_no_timings():
    assert render_lyrics(result(syncedLyrics=None, plainLyrics="Words\r\nMore words")) == (
        "Words\nMore words\n", "plain")


def test_an_instrumental_writes_nothing_rather_than_an_invented_line():
    assert render_lyrics(result(syncedLyrics=None, plainLyrics=None, instrumental=True)) == (
        None, "instrumental")
    assert render_lyrics(None) == (None, "missing")


# ------------------------------------------------------------------ plan and execute


def test_each_track_gets_a_lrc_named_after_it(tmp_path):
    seed(tmp_path)
    client = FakeLrclib({"One More Year": result(), "Instant Destiny": result(syncedLyrics=None)})

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), client))

    directory = tmp_path / ALBUM
    assert (directory / "01 - One More Year.lrc").read_text() == SYNCED
    assert (directory / "02 - Instant Destiny.lrc").read_text() == "Do you remember\n"
    assert (summary["written"], summary["synced"]) == (2, 1)


def test_an_existing_lrc_is_kept_and_not_even_looked_up(tmp_path):
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text("corrected by hand\n")
    client = FakeLrclib({"One More Year": result(), "Instant Destiny": result()})

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), client))

    assert (directory / "01 - One More Year.lrc").read_text() == "corrected by hand\n"
    assert [lookup["title"] for lookup in client.asked] == ["Instant Destiny"]
    assert (summary["kept"], summary["written"]) == (1, 1)


def test_replace_is_the_only_way_an_existing_lrc_changes(tmp_path):
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text("old\n")

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), FakeLrclib({"One More Year": result()}),
                                     replace=True))

    assert (directory / "01 - One More Year.lrc").read_text() == SYNCED
    assert summary["replaced"] == 1


def test_not_found_instrumental_and_failed_are_counted_apart(tmp_path):
    """"LRCLIB has nothing" is final; "LRCLIB didn't answer" is worth trying again."""
    seed(tmp_path, titles=("Found", "Nothing", "Wordless", "Down"))
    client = FakeLrclib({
        "Found": result(),
        "Nothing": None,
        "Wordless": result(syncedLyrics=None, plainLyrics=None, instrumental=True),
        "Down": LyricsUnavailable("LRCLIB answered 503"),
    })

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), client))

    assert {k: summary[k] for k in ("written", "missing", "instrumental", "failed")} == {
        "written": 1, "missing": 1, "instrumental": 1, "failed": 1}
    assert sorted(p.name for p in (tmp_path / ALBUM).glob("*.lrc")) == ["01 - Found.lrc"]


def test_a_track_with_no_title_tag_is_reported_not_guessed_at(tmp_path):
    directory = tmp_path / ALBUM
    write_flac(directory / "01.flac", artist="Tame Impala")

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), FakeLrclib({})))

    assert summary["untagged"] == 1
    assert not list(directory.glob("*.lrc"))


@pytest.mark.parametrize("album_path", ["../..", "../outside", "", "Tame Impala/../../outside"])
def test_nothing_outside_the_library_is_planned_or_written(tmp_path, album_path):
    library = tmp_path / "library"
    seed(library)
    outside = seed(tmp_path / "outside")

    assert plan_lyrics(album_path, str(library))["problem"]
    assert execute_lyrics(album_path, str(library), {NAMES[0]: "x\n"})["problems"]
    assert not list(outside.glob("*.lrc"))


def test_a_symlink_out_of_the_library_is_refused(tmp_path):
    library = tmp_path / "library"
    library.mkdir()
    outside = seed(tmp_path / "outside")
    (library / "link").symlink_to(outside, target_is_directory=True)

    assert plan_lyrics("link", str(library))["problem"]
    assert not list(outside.glob("*.lrc"))


@pytest.mark.parametrize("filename", ["../../../evil.flac", "Disc 2/01.flac", "cover.jpg", "missing.flac"])
def test_only_tracks_in_the_albums_own_listing_get_a_lrc(tmp_path, filename):
    directory = seed(tmp_path)
    (directory / "cover.jpg").write_bytes(b"jpg")

    results = execute_lyrics(ALBUM, str(tmp_path), {filename: "x\n"})

    assert results["written"] == []
    assert results["problems"]
    assert not list(tmp_path.rglob("*.lrc"))


# ------------------------------------------------------------------ reading for the track view


def test_the_track_view_reads_the_lrc_beside_the_file(tmp_path):
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text(SYNCED)

    lyrics = read_track_lyrics(ALBUM, str(tmp_path), NAMES[0])

    assert lyrics["source"] == "file"
    assert lyrics["synced"] is True
    assert lyrics["lines"][0] == {"time": 12.5, "text": "Do you remember"}


def test_lyrics_in_the_files_own_tags_are_the_fallback(tmp_path):
    directory = seed(tmp_path)
    write_flac(directory / NAMES[1], title="Instant Destiny", artist="Tame Impala",
               lyrics="Written by some other tagger")

    lyrics = read_track_lyrics(ALBUM, str(tmp_path), NAMES[1])

    assert (lyrics["source"], lyrics["synced"]) == ("embedded", False)
    assert lyrics["lines"] == [{"time": None, "text": "Written by some other tagger"}]


def test_a_track_with_no_lyrics_says_so_rather_than_failing(tmp_path):
    seed(tmp_path)
    lyrics = read_track_lyrics(ALBUM, str(tmp_path), NAMES[0])
    assert (lyrics["source"], lyrics["lines"]) == (None, [])


@pytest.mark.parametrize("album, filename", [
    ("../..", NAMES[0]), (ALBUM, "../../../etc/passwd"), (ALBUM, "cover.jpg"), (ALBUM, "01 - One More Year.lrc"),
])
def test_the_lyrics_route_answers_404_for_anything_but_a_track(tmp_path, monkeypatch, album, filename):
    from src.routes.library import track_lyrics

    directory = seed(tmp_path)
    (directory / "cover.jpg").write_bytes(b"jpg")
    (directory / "01 - One More Year.lrc").write_text(SYNCED)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))

    with pytest.raises(HTTPException) as refused:
        run(track_lyrics(album, filename))

    assert refused.value.status_code == 404


def test_the_fetch_route_writes_and_forgets_the_cached_album(tmp_path, monkeypatch):
    from src.routes import library as routes

    directory = seed(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(routes, "lrclib", FakeLrclib({"One More Year": result()}))
    forgotten: list[str] = []
    monkeypatch.setattr(routes, "forget_cached_album", forgotten.append)
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace()))

    summary = run(routes.fetch_lyrics(request, routes.LyricsRequest(album_path=ALBUM)))

    assert (summary["written"], summary["missing"]) == (1, 1)
    assert forgotten == [str(directory)]


# ------------------------------------------------------------------ the scan and the delete dialog


def test_the_scan_counts_tracks_with_a_lrc(tmp_path):
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text(SYNCED)
    (directory / "stray.lrc").write_text(SYNCED)

    album = read_album_dir(directory, tmp_path)

    assert (album["lyrics_count"], album["track_count"]) == (1, 2)


def test_a_tracks_own_lrc_is_not_listed_as_something_that_might_be_the_only_copy(tmp_path):
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text(SYNCED)
    (directory / "rip.log").write_text("EAC")
    (directory / "stray.lrc").write_text(SYNCED)

    summary = summarize_for_deletion(directory)

    assert sorted(summary["other_files"]) == ["rip.log", "stray.lrc"]


# ------------------------------------------------------------------ as an album is filed


def test_a_filed_album_has_its_lyrics_fetched_in_the_background(tmp_path, monkeypatch):
    from src import poller

    directory = seed(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "FETCH_LYRICS", "on")
    results = {"plan": {"album_dir": str(directory)}}

    async def go():
        task = poller._fetch_lyrics_later(results, FakeLrclib({"One More Year": result()}))
        await task

    run(go())
    assert (directory / "01 - One More Year.lrc").read_text() == SYNCED


def test_with_fetching_off_nothing_is_asked(tmp_path, monkeypatch):
    from src import poller

    directory = seed(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "FETCH_LYRICS", "off")
    client = FakeLrclib({"One More Year": result()})

    async def go():
        return poller._fetch_lyrics_later({"plan": {"album_dir": str(directory)}}, client)

    assert run(go()) is None
    assert client.asked == []


# ------------------------------------------------------------------ the LRCLIB client


def ask(handler, lookup=LOOKUP):
    seen: list[httpx.Request] = []

    def record(request):
        seen.append(request)
        return handler(request)

    async def go():
        client = LrclibClient()
        client.client = httpx.AsyncClient(base_url=BASE_URL, transport=httpx.MockTransport(record))
        try:
            return await client.find(lookup)
        finally:
            await client.close_client()

    return run(go()), seen


def test_the_exact_lookup_is_asked_first_with_every_field():
    found, seen = ask(lambda request: httpx.Response(200, json=result()))

    assert found["syncedLyrics"] == SYNCED
    assert seen[0].url.path == "/api/get"
    assert dict(seen[0].url.params) == {"track_name": "Roads", "artist_name": "Portishead",
                                        "album_name": "Dummy", "duration": "305"}
    assert seen[0].headers["user-agent"].startswith("deadwax/")


def test_a_miss_falls_back_to_search_held_to_the_duration():
    def handler(request):
        if request.url.path == "/api/get":
            return httpx.Response(404, json={"message": "not found"})
        return httpx.Response(200, json=[result(duration=400.0), result(albumName="Dummy (Deluxe)")])

    found, seen = ask(handler)

    assert [r.url.path for r in seen] == ["/api/get", "/api/search"]
    assert found["albumName"] == "Dummy (Deluxe)"


def test_nothing_anywhere_is_none_not_an_error():
    found, seen = ask(lambda request: httpx.Response(404) if request.url.path == "/api/get"
                      else httpx.Response(200, json=[]))
    assert found is None


def test_the_album_artist_is_tried_when_the_track_artist_finds_nothing():
    lookup = {**LOOKUP, "artists": ["Portishead feat. Someone", "Portishead"]}

    def handler(request):
        if request.url.params.get("artist_name") == "Portishead" and request.url.path == "/api/get":
            return httpx.Response(200, json=result())
        return httpx.Response(404) if request.url.path == "/api/get" else httpx.Response(200, json=[])

    found, seen = ask(handler, lookup)

    assert found is not None
    assert [r.url.params["artist_name"] for r in seen] == [
        "Portishead feat. Someone", "Portishead feat. Someone", "Portishead"]


def test_a_busy_lrclib_is_asked_again_before_giving_up(monkeypatch):
    from src.api import lrclib_endpoint
    monkeypatch.setattr(lrclib_endpoint, "RETRY_PAUSES", (0, 0))
    answers = iter([httpx.Response(503), httpx.Response(200, json=result())])

    found, seen = ask(lambda request: next(answers))

    assert found is not None
    assert len(seen) == 2


@pytest.mark.parametrize("handler", [
    lambda request: httpx.Response(503),
    lambda request: (_ for _ in ()).throw(httpx.ConnectError("down")),
])
def test_an_outage_raises_rather_than_passing_for_no_lyrics(handler, monkeypatch):
    from src.api import lrclib_endpoint
    monkeypatch.setattr(lrclib_endpoint, "RETRY_PAUSES", (0, 0))
    with pytest.raises(LyricsUnavailable):
        ask(handler)


def test_the_lrc_is_named_after_the_audio_file():
    assert lyrics_filename("01 - Mysterons.flac") == "01 - Mysterons.lrc"
    assert lyrics_filename("Track.v2.mp3") == "Track.v2.lrc"


# ------------------------------------------------------------------ the lead (v0.7.1)
#
# LRCLIB's timings are tapped along by people and land a moment late, which on a fast song shows
# the line just sung - seen in Amperfy on "American Capitalist". The lead moves them earlier as
# they are written, and re-timing moves files already saved, but only files that are still
# exactly LRCLIB's lyrics.

from src.config import parse_lyrics_lead  # noqa: E402
from src.lyrics import shift_lrc, timing_delta  # noqa: E402

AMERICAN_CAPITALIST = "[00:25.10] I'm a red blooded\n[00:26.56] Rough neck\n[00:27.47] Son of a bitch\n"


def test_the_lead_moves_every_line_earlier_and_nothing_else():
    assert shift_lrc(AMERICAN_CAPITALIST, 300) == (
        "[00:24.80] I'm a red blooded\n[00:26.26] Rough neck\n[00:27.17] Son of a bitch\n")


def test_no_lead_leaves_the_file_byte_for_byte():
    assert shift_lrc(AMERICAN_CAPITALIST, 0) == AMERICAN_CAPITALIST


def test_a_line_cannot_start_before_the_song_does():
    assert shift_lrc("[00:00.20] Intro\n", 300) == "[00:00.00] Intro\n"


def test_each_stamp_keeps_its_precision_and_minutes_carry():
    assert shift_lrc("[01:00.100] a\n[01:00.05] b\n", 200) == "[00:59.900] a\n[00:59.85] b\n"


def test_a_negative_lead_moves_them_later():
    assert shift_lrc("[00:59.90] a\n", -200) == "[01:00.10] a\n"


def test_header_tags_are_not_timestamps():
    assert shift_lrc("[ar:Five Finger Death Punch]\n[00:25.10] a\n", 300) == (
        "[ar:Five Finger Death Punch]\n[00:24.80] a\n")


def test_rendering_applies_the_lead_to_synced_lyrics_only():
    assert render_lyrics(result(syncedLyrics=AMERICAN_CAPITALIST), 300)[0].startswith("[00:24.80]")
    assert render_lyrics(result(syncedLyrics=None, plainLyrics="Words"), 300) == ("Words\n", "plain")


def test_the_delta_is_the_lead_a_file_was_written_at():
    assert timing_delta(AMERICAN_CAPITALIST, AMERICAN_CAPITALIST) == 0
    assert timing_delta(shift_lrc(AMERICAN_CAPITALIST, 300), AMERICAN_CAPITALIST) == 300
    assert timing_delta(shift_lrc(AMERICAN_CAPITALIST, -250), AMERICAN_CAPITALIST) == -250


def test_lines_held_at_zero_by_the_lead_still_count_as_shifted():
    source = "[00:00.20] Intro\n[00:10.00] Verse\n"
    assert timing_delta(shift_lrc(source, 300), source) == 300


def test_one_line_retimed_by_hand_is_not_a_shift():
    edited = AMERICAN_CAPITALIST.replace("[00:26.56]", "[00:26.10]")
    assert timing_delta(edited, AMERICAN_CAPITALIST) is None


def test_different_words_are_not_a_shift():
    assert timing_delta(AMERICAN_CAPITALIST.replace("Rough neck", "Roughneck"), AMERICAN_CAPITALIST) is None
    assert timing_delta("[00:25.10] I'm a red blooded\n", AMERICAN_CAPITALIST) is None


@pytest.mark.parametrize("value, lead", [
    ("300", 300), ("-200", -200), (" 300ms ", 300), ("", 0), (None, 0), ("0", 0),
    ("abc", None), ("1.5", None), ("9000", None),
])
def test_the_lead_setting_is_a_whole_number_of_milliseconds(value, lead):
    assert parse_lyrics_lead(value) == lead


def test_new_lyrics_are_written_at_the_lead(tmp_path):
    directory = seed(tmp_path)
    client = FakeLrclib({"One More Year": result(syncedLyrics=AMERICAN_CAPITALIST)})

    run(fetch_album_lyrics(ALBUM, str(tmp_path), client, lead_ms=300))

    assert (directory / "01 - One More Year.lrc").read_text().startswith("[00:24.80]")


def retime_client():
    return FakeLrclib({"One More Year": result(syncedLyrics=AMERICAN_CAPITALIST),
                       "Instant Destiny": result(syncedLyrics=AMERICAN_CAPITALIST)})


def test_a_file_written_before_the_lead_existed_is_retimed(tmp_path):
    """0.7.0 wrote LRCLIB's timings unchanged - a lead of 0 - and recorded nothing."""
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text(AMERICAN_CAPITALIST)

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), retime_client(), lead_ms=300, retime=True))

    assert summary["retimed"] == 1
    assert (directory / "01 - One More Year.lrc").read_text() == shift_lrc(AMERICAN_CAPITALIST, 300)


def test_retiming_twice_to_the_same_lead_changes_nothing_the_second_time(tmp_path):
    directory = seed(tmp_path)
    lrc = directory / "01 - One More Year.lrc"
    lrc.write_text(AMERICAN_CAPITALIST)

    run(fetch_album_lyrics(ALBUM, str(tmp_path), retime_client(), lead_ms=300, retime=True))
    once = lrc.read_text()
    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), retime_client(), lead_ms=300, retime=True))

    assert summary["unchanged"] == 1
    assert lrc.read_text() == once


def test_changing_the_lead_again_moves_from_the_old_lead_not_on_top_of_it(tmp_path):
    directory = seed(tmp_path)
    lrc = directory / "01 - One More Year.lrc"
    lrc.write_text(shift_lrc(AMERICAN_CAPITALIST, 300))

    run(fetch_album_lyrics(ALBUM, str(tmp_path), retime_client(), lead_ms=500, retime=True))

    assert lrc.read_text() == shift_lrc(AMERICAN_CAPITALIST, 500)


def test_a_file_corrected_by_hand_is_left_alone(tmp_path):
    directory = seed(tmp_path)
    corrected = AMERICAN_CAPITALIST.replace("[00:26.56]", "[00:26.10]")
    (directory / "01 - One More Year.lrc").write_text(corrected)

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), retime_client(), lead_ms=300, retime=True))

    assert summary["custom"] == 1
    assert (directory / "01 - One More Year.lrc").read_text() == corrected


def test_plain_lyrics_have_nothing_to_retime_and_lrclib_is_not_asked(tmp_path):
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text("Just words\n")
    client = retime_client()

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), client, lead_ms=300, retime=True))

    assert (summary["plain"], summary["absent"]) == (1, 1)
    assert client.asked == []
    assert (directory / "01 - One More Year.lrc").read_text() == "Just words\n"


def test_a_retime_never_writes_lyrics_a_track_did_not_have(tmp_path):
    directory = seed(tmp_path)

    run(fetch_album_lyrics(ALBUM, str(tmp_path), retime_client(), lead_ms=300, retime=True))

    assert not list(directory.glob("*.lrc"))


def test_lrclib_being_down_leaves_the_file_and_says_failed(tmp_path):
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text(AMERICAN_CAPITALIST)
    client = FakeLrclib({"One More Year": LyricsUnavailable("LRCLIB answered 503")})

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), client, lead_ms=300, retime=True))

    assert summary["failed"] == 1
    assert (directory / "01 - One More Year.lrc").read_text() == AMERICAN_CAPITALIST


def test_the_route_retimes_at_the_configured_lead(tmp_path, monkeypatch):
    from src.routes import library as routes

    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text(AMERICAN_CAPITALIST)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "LYRICS_LEAD_MS", "400")
    monkeypatch.setattr(routes, "lrclib", retime_client())
    forgotten: list[str] = []
    monkeypatch.setattr(routes, "forget_cached_album", forgotten.append)
    request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace()))

    summary = run(routes.fetch_lyrics(request, routes.LyricsRequest(album_path=ALBUM, retime=True)))

    assert summary["retimed"] == 1
    assert (directory / "01 - One More Year.lrc").read_text() == shift_lrc(AMERICAN_CAPITALIST, 400)
    assert forgotten == [str(directory)]


def test_a_filed_album_gets_its_lyrics_at_the_configured_lead(tmp_path, monkeypatch):
    from src import poller

    directory = seed(tmp_path)
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path))
    monkeypatch.setattr(Config, "FETCH_LYRICS", "on")
    monkeypatch.setattr(Config, "LYRICS_LEAD_MS", "300")

    async def go():
        await poller._fetch_lyrics_later({"plan": {"album_dir": str(directory)}}, retime_client())

    run(go())
    assert (directory / "01 - One More Year.lrc").read_text() == shift_lrc(AMERICAN_CAPITALIST, 300)


def test_a_retime_finds_the_entry_a_file_came_from_among_several(tmp_path):
    """
    LRCLIB holds several entries per song, and which one the exact lookup answers with changes
    as entries are added - Portishead's "Wandering Star" was written from one and answered with
    another an hour later. The file is re-timed against the one it actually came from.
    """
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text(AMERICAN_CAPITALIST)
    newer = AMERICAN_CAPITALIST.replace("[00:26.56]", "[00:26.90]")

    class SeveralEntries(FakeLrclib):
        async def candidates(self, lookup):
            self.asked.append(lookup)
            yield [result(syncedLyrics=newer)]
            yield [result(albumName="a single"), result(syncedLyrics=AMERICAN_CAPITALIST)]

    summary = run(fetch_album_lyrics(ALBUM, str(tmp_path), SeveralEntries({}), lead_ms=300, retime=True))

    assert summary["retimed"] == 1
    assert (directory / "01 - One More Year.lrc").read_text() == shift_lrc(AMERICAN_CAPITALIST, 300)


def test_the_client_offers_the_exact_entry_then_the_search():
    def handler(request):
        if request.url.path == "/api/get":
            return httpx.Response(200, json=result(albumName="exact"))
        return httpx.Response(200, json=[result(albumName="searched")])

    async def go():
        client = LrclibClient()
        client.client = httpx.AsyncClient(base_url=BASE_URL, transport=httpx.MockTransport(handler))
        try:
            return [[entry["albumName"] for entry in batch] async for batch in client.candidates(LOOKUP)]
        finally:
            await client.close_client()

    assert run(go()) == [["exact"], ["searched"]]


def test_a_retime_that_matches_the_exact_entry_asks_nothing_more(tmp_path):
    """One request a track, not two - a whole library at two a track is what makes LRCLIB answer 503."""
    directory = seed(tmp_path)
    (directory / "01 - One More Year.lrc").write_text(AMERICAN_CAPITALIST)
    batches_taken = []

    class Counting(FakeLrclib):
        async def candidates(self, lookup):
            batches_taken.append("exact")
            yield [result(syncedLyrics=AMERICAN_CAPITALIST)]
            batches_taken.append("search")
            yield []

    run(fetch_album_lyrics(ALBUM, str(tmp_path), Counting({}), lead_ms=300, retime=True))

    assert batches_taken == ["exact"]


def test_the_gaps_between_verses_do_not_make_a_file_look_edited():
    """LRCLIB writes untimed blank lines between verses into synced lyrics - "Wandering Star" has them."""
    verses = "[00:12.36] Please, could you stay awhile\n\n[00:17.54] For it's such a lovely day\n"
    assert timing_delta(verses, verses) == 0
    assert timing_delta(shift_lrc(verses, 300), verses) == 300


def test_a_line_whose_timestamp_was_removed_is_still_an_edit():
    source = "[00:12.36] Please\n[00:17.54] For it's such a lovely day\n"
    assert timing_delta("[00:12.36] Please\nFor it's such a lovely day\n", source) is None
