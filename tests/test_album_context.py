"""
Which album a song resampled for the player is in, and what that album says about resampling it
(src/album_context.py): the phase of the album's grid in each song, which songs beside it lend it
context, and that nothing Navidrome fails to say ever costs the song - only the exactness of a join,
said in the log.

Navidrome is a fake holding one album (AlbumNavidrome, used by test_resampled_stream.py too), behind
test_navidrome.py's fake client, and the cache is the real one. Planning needs no audio library:
its FLACs are the muxer tests' encoder's. Reading a neighbour's samples does, and those tests skip
without numpy, soxr and soundfile (never in CI - see test_resample.py).
"""

import asyncio
import logging
import sys
from collections import Counter, defaultdict
from pathlib import Path

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import album_context, player_cache, resample  # noqa: E402
from src.album_context import CannotPlan  # noqa: E402
from src.flac_mp4 import CannotRepackage, _read_metadata, _skip_id3v2  # noqa: E402
import test_navidrome as navidrome_tests  # noqa: E402
from test_flac_mp4 import encode  # noqa: E402
from test_navidrome import STAMP, failed, ok, streamed  # noqa: E402
from test_resample import ape_tag, constant_flac, libraries, metadata, music, write_flac  # noqa: E402

#? test_navidrome.py's fake Navidrome client and a cache of the test's own, as test_player_cache.py
#? takes them
configured, upstream, mp4_cache = navidrome_tests.configured, navidrome_tests.upstream, navidrome_tests.mp4_cache

LATER = "Sun, 27 Sep 2026 09:00:00 GMT"


class AlbumNavidrome:
    """
    Navidrome holding one album, in order. `getSong` names the album, `getAlbum` lists its songs
    (with the samplingRate, bitDepth and channelCount it sends every client not listed as legacy),
    and each song's file is served whole or by range as Go's ServeContent serves it - If-Range
    included: a validator other than the file's own Last-Modified gets the whole file. What it was
    asked is kept, and anything about it can be changed between requests.
    """

    def __init__(self, songs: dict[str, bytes], album_id: str = "album-1"):
        self.files = dict(songs)
        self.album_id = album_id
        self.modified = {song: STAMP for song in self.files}
        self.types = {song: "audio/flac" for song in self.files}
        self.entries = {song: self.entry(i, song, data) for i, (song, data) in enumerate(self.files.items())}
        #? the songs getAlbum lists, in order
        self.listed = list(self.files)
        #? JSON calls answered 500, and files whose ranges are
        self.failing: set[str] = set()
        self.calls: list[tuple[str, str]] = []
        self.ranges: dict[str, list[str]] = defaultdict(list)
        self.whole: Counter = Counter()

    def entry(self, index: int, song: str, data: bytes) -> dict:
        said = {}
        try:
            info, _ = _read_metadata(data, _skip_id3v2(data))
            said = {"samplingRate": info.sample_rate, "bitDepth": info.bits_per_sample,
                    "channelCount": info.channels, "duration": info.total_samples // info.sample_rate}
        except CannotRepackage:
            pass
        return {"id": song, "title": song.title(), "albumId": self.album_id, "track": index + 1, "discNumber": 1,
                "suffix": "flac", "contentType": "audio/flac", **said}

    def handle(self, request: httpx.Request) -> httpx.Response:
        name = request.url.path.rsplit("/", 1)[-1]
        song = request.url.params.get("id")
        if name in ("getSong", "getAlbum"):
            self.calls.append((name, song))
            if name in self.failing:
                return httpx.Response(500, text="boom")
            if name == "getSong":
                return httpx.Response(200, json=ok(song=self.entries[song]))
            if song != self.album_id:
                return httpx.Response(200, json=failed(70, "Album not found"))
            return httpx.Response(200, json=ok(album={"id": self.album_id, "name": "Album",
                                                      "song": [self.entries[s] for s in self.listed]}))
        if name == "stream":
            return self.serve(song, request)
        return httpx.Response(404)

    def serve(self, song: str, request: httpx.Request) -> httpx.Response:
        data = self.files[song]
        headers = {"content-type": self.types[song], "accept-ranges": "bytes", "last-modified": self.modified[song]}
        wanted = request.headers.get("range")
        if wanted and song in self.failing:
            return httpx.Response(500, text="boom")
        if wanted and request.headers.get("if-range") not in (None, self.modified[song]):
            wanted = None
        if not wanted:
            self.whole[song] += 1
            return streamed(200, data, headers)
        self.ranges[song].append(wanted)
        start, _, end = wanted.removeprefix("bytes=").partition("-")
        if start == "":
            start, end = max(0, len(data) - int(end)), len(data) - 1
        start, end = int(start), min(int(end), len(data) - 1) if end else len(data) - 1
        if start >= len(data):
            return httpx.Response(416, text="invalid range\n", headers={
                "content-type": "text/plain; charset=utf-8", "content-range": f"bytes */{len(data)}"})
        return streamed(206, data[start:end + 1], {**headers, "content-range": f"bytes {start}-{end}/{len(data)}"})


def hires(blocks, rate: int = 192000, bps: int = 24, channels: int = 2, seed: int = 1, **more) -> bytes:
    """A small valid FLAC of that shape: constant frames, a dozen bytes each."""
    return encode(rate=rate, bps=bps, channels=channels, blocks=blocks, constant=True, seed=seed, **more)[0]


def length(data: bytes) -> int:
    return _read_metadata(data, _skip_id3v2(data))[0].total_samples


def serving(state, songs: dict[str, bytes]) -> AlbumNavidrome:
    album = AlbumNavidrome(songs)
    state["handler"] = album.handle
    return album


def plan_of(cache: player_cache.Mp4Cache, song: str, max_rate: int = 48000):
    async def ask():
        version = await cache._version(song)
        return version, await cache.albums.plan(version, max_rate)
    return asyncio.run(ask())


def later(cache: player_cache.Mp4Cache, seconds: float = player_cache.VERSION_SECONDS + 1) -> None:
    """Move the cache's clock on - past what Navidrome said being believed, by default."""
    now = cache.clock() + seconds
    cache.clock = lambda: now


# ---------------------------------------------------------------- the grid

def test_the_phase_counts_the_songs_on_the_grid_before_it(upstream, mp4_cache):
    """
    The phase is album_phase() of the samples of the songs before it at its rate - not the CD-rate
    bonus track, not the MP3, not the 96 kHz interlude, which are resampled on grids of their own
    or not at all - and every song on the grid works it out from the same listing.
    """
    state, _ = upstream
    songs = {
        "cd": hires((4096,) * 3 + (7,), rate=44100, bps=16),
        "one": hires((4096,) * 5 + (1001,)),
        "mp3": b"\xff\xfb\x90\x00" + bytes(4000),
        "two": hires((4096,) * 4 + (2002,)),
        "interlude": hires((4096,) * 2 + (3,), rate=96000),
        "three": hires((4096,) * 3 + (5,)),
    }
    album = serving(state, songs)
    album.entries["mp3"].update(suffix="mp3", contentType="audio/mpeg")
    album.types["mp3"] = "audio/mpeg"

    phases = {song: plan_of(mp4_cache, song)[1].phase for song in ("one", "two", "three")}

    assert phases == {"one": 0, "two": resample.album_phase(length(songs["one"]), 4),
                      "three": resample.album_phase(length(songs["one"]) + length(songs["two"]), 4)}
    assert phases["three"] == resample.next_phase(phases["two"], length(songs["two"]), 4)
    assert "mp3" not in album.ranges, "not a FLAC by its listing: never looked at"
    assert plan_of(mp4_cache, "cd")[1] is None
    interlude = plan_of(mp4_cache, "interlude")[1]
    assert (interlude.ratio, interlude.phase) == (2, resample.album_phase(0, 2))


def test_the_songs_beside_it_lend_it_context_by_version(upstream, mp4_cache):
    state, _ = upstream
    songs = {"one": hires((4096,) * 5 + (1001,)), "two": hires((4096,) * 4 + (2002,), seed=2),
             "three": hires((4096,) * 3 + (5,), seed=3)}
    serving(state, songs)

    version, plan = plan_of(mp4_cache, "two")
    before_version = asyncio.run(mp4_cache._version("one"))

    assert (plan.source_rate, plan.out_rate, plan.channels, plan.bits) == (192000, 48000, 2, 24)
    assert plan.total_samples == length(songs["two"])
    assert plan.before.song_id == "one" and plan.after.song_id == "three"
    assert plan.before.version_key == before_version.key and plan.before.size == len(songs["one"])
    assert plan.before.validator == STAMP
    assert plan.after.audio_offset == metadata(songs["three"])[1]
    assert plan.after.info.total_samples == length(songs["three"])
    assert plan_of(mp4_cache, "one")[1].before is None and plan_of(mp4_cache, "three")[1].after is None


def test_a_song_beside_it_on_another_grid_lends_nothing(upstream, mp4_cache):
    """Another rate, another channel count, a depth that isn't resampled: that join goes without
    context - the page never joins such songs anyway."""
    state, _ = upstream
    songs = {"mono": hires((4096,) * 2 + (9,), channels=1), "song": hires((4096,) * 2 + (9,)),
             "twenty": constant_flac(bps=20, blocks=(4096,) * 3)}
    serving(state, songs)

    _, plan = plan_of(mp4_cache, "song")

    assert plan.before is None and plan.after is None and plan.phase == 0


def test_a_song_the_cap_doesnt_touch_asks_nothing_of_its_album(upstream, mp4_cache):
    state, _ = upstream
    album = serving(state, {"cd": hires((4096,) * 3 + (7,), rate=44100, bps=16),
                            "twenty": constant_flac(bps=20), "thirty-two": constant_flac(bps=32),
                            "odd": hires((4096,) * 2 + (7,), rate=64000)})

    assert [plan_of(mp4_cache, song)[1] for song in album.files] == [None, None, None, None]
    assert album.calls == [], "no getSong, no getAlbum"


def test_songs_listed_at_another_rate_are_never_fetched(upstream, mp4_cache):
    state, _ = upstream
    songs = {"cd": hires((4096,) * 3 + (7,), rate=44100, bps=16), "song": hires((4096,) * 2 + (9,))}
    album = serving(state, songs)

    plan_of(mp4_cache, "song")

    assert "cd" not in album.ranges, "its listing said 44.1 kHz"


def test_a_listing_that_says_no_rate_rules_nothing_out(upstream, mp4_cache):
    """A Navidrome that lists no samplingRate, bitDepth or channelCount (one older than those fields,
    or a client it lists as legacy) has said nothing against any FLAC being on the grid: each is
    looked at, its own STREAMINFO decides, and the plan is the one the full listing gives."""
    state, _ = upstream
    songs = {"cd": hires((4096,) * 3 + (7,), rate=44100, bps=16), "one": hires((4096,) * 5 + (1001,)),
             "two": hires((4096,) * 4 + (2002,), seed=2), "three": hires((4096,) * 3 + (5,), seed=3)}
    album = serving(state, songs)
    for entry in album.entries.values():
        for field in ("samplingRate", "bitDepth", "channelCount"):
            entry.pop(field)

    _, plan = plan_of(mp4_cache, "two")

    assert plan.phase == resample.album_phase(length(songs["one"]), 4) != 0
    assert plan.before.song_id == "one" and plan.after.song_id == "three"
    assert "cd" in album.ranges, "nothing in its listing ruled it out, so it was looked at"


def test_a_song_whose_length_isnt_known_lends_no_context_either_side(upstream, mp4_cache):
    """A song whose STREAMINFO says 0 samples counts as 0 towards the phase, so neither of its joins
    could be exact: no context across them."""
    state, _ = upstream
    songs = {"unknown": hires((4096,) * 2 + (9,), total=0), "song": hires((4096,) * 2 + (9,))}
    serving(state, songs)

    _, plan = plan_of(mp4_cache, "song")
    _, itself = plan_of(mp4_cache, "unknown")

    assert plan.before is None and plan.phase == 0
    assert itself is None, "its own grid can't be known: sent as it is"


# ---------------------------------------------------------------- STREAMINFO

def with_a_cover(data: bytes, id3: int, cover: int) -> bytes:
    """The same FLAC with an ID3v2 tag of `id3` bytes in front, and after its STREAMINFO a PICTURE
    block of `cover` bytes and then a small PADDING block - the block whose header lies past the
    cover is what makes the walk read again."""
    info, audio = metadata(data)
    size = id3 - 10
    front = b"ID3\x04\x00\x00" + bytes(((size >> 21) & 0x7F, (size >> 14) & 0x7F, (size >> 7) & 0x7F,
                                         size & 0x7F)) + bytes(size)
    blocks = (bytes((0x00, 0, 0, 34)) + info.raw + bytes((0x06,)) + cover.to_bytes(3, "big") + bytes(cover)
              + bytes((0x81, 0, 0, 64)) + bytes(64))
    return front + b"fLaC" + blocks + data[audio:]


def test_streaminfo_is_found_behind_an_id3_tag_and_the_audio_behind_a_big_cover(upstream, mp4_cache):
    """The STREAMINFO is in the first 64 KiB; a cover bigger than that costs one more read, where the
    next block's header is, for where the audio starts - never a read of the cover itself."""
    state, _ = upstream
    plain = hires((4096,) * 3 + (7,))
    tagged = with_a_cover(plain, id3=4096, cover=300_000)
    album = serving(state, {"song": tagged})

    version = asyncio.run(mp4_cache._version("song"))
    info, audio = asyncio.run(mp4_cache.albums.stream_info(version))

    assert (info.sample_rate, info.total_samples) == (192000, length(plain))
    assert audio == metadata(tagged)[1] > 300_000
    assert album.ranges["song"] == ["bytes=0-3", "bytes=0-65535", f"bytes={audio - 68}-{len(tagged) - 1}"]
    asyncio.run(mp4_cache.albums.stream_info(version))
    assert len(album.ranges["song"]) == 3, "remembered by version"


def test_the_audio_is_found_behind_a_booklet_of_embedded_pictures(upstream, mp4_cache):
    """A rip with its booklet embedded: a picture a page, each bigger than a read, so each costs one
    more read for the header after it - thirty of them still say where the audio starts, so the song
    before it still gets its start as context. At 8 reads it never did."""
    state, _ = upstream
    plain = hires((4096,) * 3 + (7,))
    info, audio = metadata(plain)
    pages = b"".join(bytes((0x06,)) + (100_000).to_bytes(3, "big") + bytes(100_000) for _ in range(30))
    booklet = b"fLaC" + bytes((0x00, 0, 0, 34)) + info.raw + pages + bytes((0x81, 0, 0, 64)) + bytes(64) + plain[audio:]
    album = serving(state, {"song": booklet})

    version = asyncio.run(mp4_cache._version("song"))
    _, found = asyncio.run(mp4_cache.albums.stream_info(version))

    assert found == metadata(booklet)[1] > 3_000_000
    assert len(album.ranges["song"]) == 32, "the version's look, then a read for each page's end"


def test_the_songs_own_file_that_cant_be_read_just_now_cant_be_planned(upstream, mp4_cache):
    state, _ = upstream
    album = serving(state, {"song": hires((4096,) * 2 + (9,))})
    version = asyncio.run(mp4_cache._version("song"))
    album.failing.add("song")

    with pytest.raises(CannotPlan):
        asyncio.run(mp4_cache.albums.plan(version, 48000))
    album.failing.clear()
    assert asyncio.run(mp4_cache.albums.plan(version, 48000)) is not None, "a failure isn't remembered"


# ---------------------------------------------------------------- when Navidrome won't say

def test_an_album_navidrome_wont_list_is_the_song_resampled_alone_said_once(upstream, mp4_cache, caplog):
    state, _ = upstream
    album = serving(state, {"one": hires((4096,) * 2 + (9,)), "two": hires((4096,) * 2 + (9,), seed=2)})
    album.failing.add("getAlbum")
    caplog.set_level(logging.INFO)

    _, plan = plan_of(mp4_cache, "two")
    _, again = plan_of(mp4_cache, "two")

    assert plan == again and (plan.phase, plan.before, plan.after) == (0, None, None)
    lines = [r for r in caplog.records if "resampled without its album around it" in r.getMessage()]
    assert len(lines) == 1 and lines[0].levelno == logging.WARNING
    assert "may not be exact" in lines[0].getMessage()


def test_a_plan_is_kept_across_a_navidrome_hiccup(upstream, mp4_cache, caplog):
    """The plan is in the cache key: a hiccup that made the song a plan without context would make
    it again, beside itself. The plan last made stands until the album can be looked at again."""
    state, _ = upstream
    album = serving(state, {"one": hires((4096,) * 2 + (9,)), "two": hires((4096,) * 2 + (9,), seed=2)})
    caplog.set_level(logging.INFO)
    version, first = plan_of(mp4_cache, "two")
    assert first.before is not None

    later(mp4_cache)
    album.failing.add("getSong")
    kept = asyncio.run(mp4_cache.albums.plan(version, 48000))

    assert kept == first and version.key_for(player_cache.FMP4_WRAP, kept) == version.key_for(
        player_cache.FMP4_WRAP, first)
    assert any("resampled as it was last time" in r.getMessage() for r in caplog.records)
    assert not any("without its album" in r.getMessage() for r in caplog.records)


@pytest.mark.parametrize("how", ["not listed", "no such album"])
def test_a_song_its_album_doesnt_list_is_resampled_alone(upstream, mp4_cache, caplog, how):
    state, _ = upstream
    album = serving(state, {"one": hires((4096,) * 2 + (9,)), "two": hires((4096,) * 2 + (9,), seed=2)})
    if how == "not listed":
        album.listed = ["one"]
    else:
        album.entries["two"]["albumId"] = "another-album"

    _, plan = plan_of(mp4_cache, "two")

    assert (plan.phase, plan.before, plan.after) == (0, None, None)
    assert any("without its album around it" in r.getMessage() for r in caplog.records)


class Refusing(AlbumNavidrome):
    """The album, with some songs' files answered another way (`answers`): a status, a Subsonic
    failure in a 200, or a connection refused - nothing answering at all."""

    def __init__(self, songs: dict[str, bytes], answers: dict):
        super().__init__(songs)
        self.answers = answers

    def serve(self, song: str, request: httpx.Request) -> httpx.Response:
        how = self.answers.get(song)
        if how == "refused":
            raise httpx.ConnectError("connection refused", request=request)
        if how == "subsonic":
            return httpx.Response(200, json=failed(70, "Song not found"))
        if how is not None:
            return httpx.Response(how, text="nope")
        return super().serve(song, request)


FOUR = {"one": hires((4096,) * 5 + (1001,)), "two": hires((4096,) * 4 + (2002,), seed=2),
        "three": hires((4096,) * 3 + (5,), seed=3), "four": hires((4096,) * 2 + (7,), seed=4)}


def plans_with(state, cache, answers: dict, songs=("two", "three", "four")) -> dict:
    album = Refusing(FOUR, answers)
    state["handler"] = album.handle
    summary = {}
    for song in songs:
        plan = plan_of(cache, song)[1]
        summary[song] = (plan.phase, plan.before and plan.before.song_id, plan.after and plan.after.song_id)
    return summary


@pytest.mark.parametrize("answer", [404, 500, "subsonic"])
def test_a_song_navidrome_answers_for_but_wont_serve_is_off_the_grid(upstream, mp4_cache, caplog, answer):
    """
    A song of the album whose file Navidrome answers about but won't serve - gone from disk until the
    next scan, unreadable - can't be played either, so it is off the grid, as a file that isn't a FLAC
    is: the songs after it work the grid out without it, and only its own joins go without context.
    Taken for the album not being known, it took the grid and the context away from every song after
    it, and the joins between readable songs clicked.
    """
    state, _ = upstream
    phase = lambda *songs: resample.album_phase(sum(length(FOUR[s]) for s in songs), 4)  # noqa: E731

    plans = plans_with(state, mp4_cache, {"one": answer})

    assert plans == {"two": (0, None, "three"), "three": (phase("two"), "two", "four"),
                     "four": (phase("two", "three"), "three", None)}
    lines = [r for r in caplog.records if "isn't counted in its album's sample grid" in r.getMessage()]
    assert lines and lines[0].levelno == logging.WARNING and "song one" in lines[0].getMessage()
    assert not any("without its album around it" in r.getMessage() for r in caplog.records)


def test_the_next_song_navidrome_wont_serve_costs_the_song_before_it_only_that_join(upstream, mp4_cache):
    state, _ = upstream
    plans = plans_with(state, mp4_cache, {"four": 500}, songs=("two", "three"))
    assert plans["three"] == (resample.album_phase(length(FOUR["one"]) + length(FOUR["two"]), 4), "two", None)
    assert plans["two"][1:] == ("one", "three")


def test_a_song_navidrome_doesnt_answer_for_at_all_is_still_the_album_not_known(upstream, mp4_cache):
    """Nothing answering - refused, timed out - may be Navidrome itself, not the song: the kept plan,
    or the song alone, as ever."""
    state, _ = upstream
    plans = plans_with(state, mp4_cache, {"one": "refused"}, songs=("three",))
    assert plans["three"] == (0, None, None)


# ---------------------------------------------------------------- one plan at a time

def racing(state, fail_the_second_after: float) -> AlbumNavidrome:
    """The album, a little slow to answer - and the SECOND getSong for song "two" answered 500 after
    `fail_the_second_after` seconds: a hiccup that meets one request of two in flight."""
    album = AlbumNavidrome({"one": hires((4096,) * 2 + (9,)), "two": hires((4096,) * 2 + (9,), seed=2),
                            "three": hires((4096,) * 2 + (9,), seed=3)})
    asked = Counter()

    async def handle(request):
        name = request.url.path.rsplit("/", 1)[-1]
        if name == "getSong" and request.url.params.get("id") == "two":
            asked["getSong"] += 1
            if asked["getSong"] == 2:
                await asyncio.sleep(fail_the_second_after)
                return httpx.Response(500, text="boom")
        await asyncio.sleep(0.01)
        return album.handle(request)

    state["handler"] = handle
    return album


@pytest.mark.parametrize("delay", [0.5, 0.0], ids=["the second fails after the first is kept", "the second fails first"])
def test_two_first_requests_at_once_wait_on_one_plan(upstream, mp4_cache, delay):
    """
    Safari's first two bytes and the readout's ask come together on every fresh song. Made side by
    side, a hiccup meeting only one of them made it a plan without its album - another key, another
    file, and on the MP4 path Safari carried on from a file of another length than its probe said.
    Now both wait on one plan: the same for both, kept, and handed to the next request too.
    """
    state, _ = upstream
    album = racing(state, delay)

    async def ask():
        version = await mp4_cache._version("two")
        a, b = await asyncio.gather(mp4_cache.albums.plan(version, 48000), mp4_cache.albums.plan(version, 48000))
        kept = mp4_cache.albums._plans[(version.key, 48000)][1]
        return a, b, kept, await mp4_cache.albums.plan(version, 48000)

    a, b, kept, third = asyncio.run(ask())

    assert a == b == kept == third and a.before is not None
    assert [c for c in album.calls if c[0] == "getSong"] == [("getSong", "two")], "one plan made"
    assert mp4_cache.albums._making == {}


def test_a_request_that_hangs_up_leaves_the_plan_to_the_other(upstream, mp4_cache):
    state, _ = upstream
    album = racing(state, 0.0)

    async def ask():
        version = await mp4_cache._version("two")
        first = asyncio.ensure_future(mp4_cache.albums.plan(version, 48000))
        second = asyncio.ensure_future(mp4_cache.albums.plan(version, 48000))
        await asyncio.sleep(0.005)
        first.cancel()
        return await second, first.cancelled()

    got, cancelled = asyncio.run(ask())

    assert cancelled and got.before is not None and got.after is not None
    assert [c for c in album.calls if c[0] == "getSong"] == [("getSong", "two")]
    assert mp4_cache.albums._making == {}


def test_what_navidrome_said_is_believed_for_as_long_as_versions_are(upstream, mp4_cache):
    state, _ = upstream
    album = serving(state, {"one": hires((4096,) * 2 + (9,)), "two": hires((4096,) * 2 + (9,), seed=2)})

    plan_of(mp4_cache, "two")
    plan_of(mp4_cache, "two")
    assert album.calls == [("getSong", "two"), ("getAlbum", "album-1")]

    later(mp4_cache)
    plan_of(mp4_cache, "two")
    assert album.calls[2:] == [("getSong", "two"), ("getAlbum", "album-1")]


def test_a_neighbour_that_changed_makes_a_new_plan_once_it_is_looked_at_again(upstream, mp4_cache):
    state, _ = upstream
    album = serving(state, {"one": hires((4096,) * 2 + (9,)), "two": hires((4096,) * 2 + (9,), seed=2)})
    version, first = plan_of(mp4_cache, "two")

    album.modified["one"] = LATER
    _, same = plan_of(mp4_cache, "two")
    later(mp4_cache)
    _, changed = plan_of(mp4_cache, "two")

    assert same == first, "within VERSION_SECONDS, as the song's own version is"
    assert changed.before.version_key != first.before.version_key
    assert version.key_for(player_cache.FMP4_WRAP, changed) != version.key_for(player_cache.FMP4_WRAP, first)


# ---------------------------------------------------------------- the context, as a song is made

def context_of(cache: player_cache.Mp4Cache, song: str):
    async def ask():
        version = await cache._version(song)
        plan = await cache.albums.plan(version, 48000)
        return await cache.albums.context(plan, song)
    return asyncio.run(ask())


def test_the_context_is_the_neighbours_own_samples(upstream, mp4_cache, tmp_path):
    np, sf, _ = libraries()
    samples = music(np, 192000, 150000)
    files = {}
    for name, (a, b) in {"one": (0, 60001), "two": (60001, 100003), "three": (100003, 150000)}.items():
        files[name] = write_flac(sf, tmp_path / f"{name}.flac", samples[a:b], 192000).read_bytes()
    state, _ = upstream
    album = serving(state, files)

    before, after = context_of(mp4_cache, "two")

    assert np.array_equal(before, samples[60001 - resample.CONTEXT_SAMPLES:60001] / (1 << 23))
    assert np.array_equal(after, samples[100003:100003 + resample.CONTEXT_SAMPLES] / (1 << 23))
    assert album.whole == Counter(), "nothing fetched whole: only ranges of the neighbours"


def test_a_neighbour_changed_since_it_was_looked_at_lends_nothing_and_it_is_said(upstream, mp4_cache, caplog):
    """Its read carries If-Range, and a file changed since comes back whole - never read."""
    state, _ = upstream
    album = serving(state, {"one": hires((4096,) * 8 + (9,)), "two": hires((4096,) * 8 + (9,), seed=2)})
    version = asyncio.run(mp4_cache._version("two"))
    plan = asyncio.run(mp4_cache.albums.plan(version, 48000))
    album.modified["one"] = LATER

    before, after = asyncio.run(mp4_cache.albums.context(plan, "two"))

    assert before is None and after is None
    lines = [r.getMessage() for r in caplog.records if "without the song before" in r.getMessage()]
    assert len(lines) == 1 and "changed since it was looked at" in lines[0] and "may not be exact" in lines[0]
    assert album.whole["one"] == 1, "answered whole, and let go of"


def test_a_tag_after_the_audio_bigger_than_the_read_is_read_past(upstream, mp4_cache, tmp_path):
    np, sf, _ = libraries()
    samples = music(np, 192000, 90000)
    one = write_flac(sf, tmp_path / "one.flac", samples[:50001], 192000).read_bytes()
    two = write_flac(sf, tmp_path / "two.flac", samples[50001:], 192000).read_bytes()
    tagged = one + ape_tag(b"cover" * 60000)
    state, _ = upstream
    album = serving(state, {"one": tagged, "two": two})

    before, _ = context_of(mp4_cache, "two")

    assert np.array_equal(before, samples[50001 - resample.CONTEXT_SAMPLES:50001] / (1 << 23))
    assert len(album.ranges["one"]) >= 2 + 2, "the probe, STREAMINFO, then the end twice"


def test_a_context_read_is_bounded_in_time(upstream, mp4_cache, monkeypatch):
    """A Navidrome that doesn't answer a neighbour's range holds the make CONTEXT_SECONDS at most,
    and the join goes without."""
    state, _ = upstream
    serving(state, {"one": hires((4096,) * 2 + (9,)), "two": hires((4096,) * 2 + (9,), seed=2)})
    version = asyncio.run(mp4_cache._version("two"))
    plan = asyncio.run(mp4_cache.albums.plan(version, 48000))
    monkeypatch.setattr(album_context, "CONTEXT_SECONDS", 0.1)

    async def hang(*args, **kwargs):
        await asyncio.sleep(5)

    monkeypatch.setattr(mp4_cache.albums, "_range", hang)
    before, after = asyncio.run(asyncio.wait_for(mp4_cache.albums.context(plan, "two"), 2))
    assert before is None and after is None
