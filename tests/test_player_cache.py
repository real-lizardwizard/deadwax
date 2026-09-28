"""
The player's MP4 cache: what happens around the repackage rather than in it.

src/player_cache.py's happy paths - an MP4 made, served by range, remade for a new version, the
least recently played going first - are pinned in test_navidrome.py. These are the ways the
review of 1.1.0-player.3 found it going wrong, each written from the scenario it measured:

  - skipping through songs in Safari made the song landed on wait for every song skipped past,
    since nothing stopped a make nobody wanted and one lock covered the downloads as well as the
    repackage;
  - one URL answered as the FLAC on one request and the MP4 on the next, which the element splices
    into a decode error;
  - a disk short of space filled up and was never given back;
  - a read-only root filesystem stopped deadwax starting at all;
  - a cache folder somebody else made first was used - listed, deleted from and served from;

and the two settings James asked for, so the cache can go on an SSD: PLAYER_CACHE_PATH and
PLAYER_CACHE_MB, saved through the real app and taking effect without a restart.

Navidrome is test_navidrome.py's fake, and the app is the real one start() builds, without its
lifespan, so nothing connects anywhere.
"""

import asyncio
import errno
import json
import logging
import os
import stat
import subprocess
import sys
import tempfile
import time
from collections import namedtuple
from contextlib import suppress
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import player_cache  # noqa: E402
from src.api.app import start  # noqa: E402
from src.config import Config, parse_player_cache_mb, player_cache_bytes  # noqa: E402
from src.player_cache import FOLDER_NAME, Mp4Cache, continues  # noqa: E402
from src.routes import download as download_routes  # noqa: E402
from src.store import JobStore  # noqa: E402
import test_navidrome as navidrome_tests  # noqa: E402
from test_navidrome import FLAC, MP4, STAMP, WRAPPED, cached, navidrome_file, streamed  # noqa: E402

#? test_navidrome.py's fake Navidrome, the real app, and a cache in a folder of the test's own -
#? that one autouse, so every test here starts with nothing cached and nothing remembered
configured, upstream, client, mp4_cache = (navidrome_tests.configured, navidrome_tests.upstream,
                                           navidrome_tests.client, navidrome_tests.mp4_cache)

ROOT = Path(__file__).resolve().parent.parent


class Probe:
    """What cache.answer() reads of a request: its headers."""

    def __init__(self, range_header: str | None = None):
        self.headers = {"range": range_header} if range_header else {}


class Unhurried(httpx.AsyncByteStream):
    """
    A whole-file download that takes its time, and says what became of it: `finished` if it was
    read to the end, `closed` when deadwax let go of it. `hold` (an asyncio.Event) keeps it waiting
    after its first chunk until set.
    """

    def __init__(self, data: bytes, step: float = 0.02, hold: asyncio.Event | None = None):
        self.data, self.step, self.hold = data, step, hold
        self.finished = self.closed = False

    async def __aiter__(self):
        for offset in range(0, len(self.data), 16384):
            if offset and self.hold is not None:
                await self.hold.wait()
            await asyncio.sleep(self.step)
            yield self.data[offset:offset + 16384]
        self.finished = True

    async def aclose(self):
        self.closed = True


def unhurried_navidrome(state, songs: dict[str, bytes] | None = None, step: float = 0.02, hold=None):
    """
    Navidrome answering a range at once, and a whole file slowly. Returns every whole-file body it
    sent, by song id, so a test can see which downloads deadwax let go of part-way.
    """
    bodies: dict[str, list[Unhurried]] = {}

    def handle(request: httpx.Request) -> httpx.Response:
        song = request.url.params["id"]
        data = (songs or {}).get(song, FLAC)
        if request.headers.get("range"):
            return navidrome_file(data)[1](request)
        body = Unhurried(data, step=step, hold=hold)
        bodies.setdefault(song, []).append(body)
        return httpx.Response(200, stream=body, headers={
            "content-type": "audio/flac", "content-length": str(len(data)), "last-modified": STAMP})

    state["handler"] = handle
    return bodies


async def body_of(response) -> bytes:
    return b"".join([chunk async for chunk in response.body_iterator])


def leftovers(cache: Mp4Cache) -> list[str]:
    """Anything in the cache folder that isn't a finished MP4 - a .part or .tmp left behind."""
    return sorted(p.name for p in cache.directory.iterdir() if p.suffix != ".mp4") if cache.directory.exists() else []


def said(caplog, words: str) -> list[logging.LogRecord]:
    return [record for record in caplog.records if words in record.getMessage()]


# ---------------------------------------------------------------- skipping songs

def test_a_make_nobody_waits_for_any_more_stops_download_and_all(upstream, mp4_cache, caplog):
    """
    Safari's element and the readout's probe both let go of a song skipped past. Nothing then waits
    for its MP4, so its download from Navidrome stops part-way and nothing is left behind.
    """
    state, _ = upstream
    bodies = unhurried_navidrome(state)
    caplog.set_level(logging.INFO)

    async def skip():
        ask = asyncio.ensure_future(mp4_cache.answer("song-1", Probe("bytes=0-1")))
        await asyncio.sleep(0.08)
        ask.cancel()
        with suppress(asyncio.CancelledError):
            await ask
        await asyncio.sleep(0.1)

    asyncio.run(skip())

    [body] = bodies["song-1"]
    assert body.closed and not body.finished, "the download was let go of part-way"
    assert cached(mp4_cache) == [] and leftovers(mp4_cache) == []
    assert mp4_cache._working == {}, "a request for it after this starts afresh"
    assert said(caplog, "was stopped - nobody was waiting for it")


def test_a_make_another_request_waits_for_carries_on(upstream, mp4_cache):
    """The element hanging up must not cancel what the gapless download (say) still waits for."""
    state, _ = upstream
    bodies = unhurried_navidrome(state)

    async def two_then_one():
        probe = asyncio.ensure_future(mp4_cache.answer("song-1", Probe("bytes=0-1")))
        whole = asyncio.ensure_future(mp4_cache.answer("song-1", Probe()))
        await asyncio.sleep(0.08)
        probe.cancel()
        response = await whole
        return response.status_code, await body_of(response)

    assert asyncio.run(two_then_one()) == (200, MP4)
    [body] = bodies["song-1"]
    assert body.finished, "one download, read to the end"


def test_downloads_dont_wait_on_each_other(upstream, mp4_cache):
    """
    One repackage at a time, since it holds the song in memory - but the lock is around that
    alone, so a song whose download is slow doesn't hold up the next one's.
    """
    state, _ = upstream

    async def while_one_is_stuck():
        stuck = asyncio.Event()
        slow = Unhurried(FLAC, hold=stuck)

        def handle(request):
            if request.headers.get("range"):
                return navidrome_file()[1](request)
            if request.url.params["id"] == "stuck":
                return httpx.Response(200, stream=slow, headers={
                    "content-type": "audio/flac", "content-length": str(len(FLAC)), "last-modified": STAMP})
            return streamed(200, FLAC, {"content-type": "audio/flac", "last-modified": STAMP})

        state["handler"] = handle
        first = asyncio.ensure_future(mp4_cache.answer("stuck", Probe("bytes=0-1")))
        await asyncio.sleep(0.05)
        second = await asyncio.wait_for(mp4_cache.answer("free", Probe("bytes=0-1")), timeout=2)
        still_stuck = not first.done()
        stuck.set()
        await first
        return second.status_code, second.headers["content-type"], still_stuck

    assert asyncio.run(while_one_is_stuck()) == (206, "audio/mp4", True)


def asgi_get(app, path: str, query: str, hang_up_after: float | None, sent: list, headers=()):
    """
    One GET through the app as uvicorn would make it: the request, then nothing until the phone
    hangs up (`hang_up_after` seconds on, or never). uvicorn never cancels the handler itself.
    """
    async def run():
        gone = asyncio.Event()
        if hang_up_after is not None:
            asyncio.get_running_loop().call_later(hang_up_after, gone.set)
        first = True

        async def receive():
            nonlocal first
            if first:
                first = False
                return {"type": "http.request", "body": b"", "more_body": False}
            await gone.wait()
            return {"type": "http.disconnect"}

        async def send(message):
            sent.append((time.monotonic(), message))

        scope = {
            "type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "GET",
            "scheme": "http", "path": path, "root_path": "", "raw_path": path.encode(),
            "query_string": query.encode(), "headers": [(b"host", b"test"), *headers],
            "server": ("test", 80), "client": ("phone", 1),
        }
        await app(scope, receive, send)

    return run()


def test_a_phone_that_hangs_up_stops_the_make_through_the_real_app(upstream, mp4_cache, monkeypatch):
    """
    Through start()'s app, the way uvicorn serves it: the route notices the phone has gone - it
    looks, since uvicorn doesn't cancel it - and the download it was waiting on stops.
    """
    state, _ = upstream
    bodies = unhurried_navidrome(state, step=0.05)
    monkeypatch.setattr(download_routes, "DISCONNECT_CHECK_SECONDS", 0.02)
    app = start()
    sent = []

    async def hang_up():
        await asgi_get(app, "/deadwax/navidrome/stream/song-1", "format=raw&wrap=mp4", 0.15, sent,
                       headers=[(b"range", b"bytes=0-1")])
        await asyncio.sleep(0.2)

    asyncio.run(hang_up())

    [body] = bodies["song-1"]
    assert body.closed and not body.finished
    assert cached(mp4_cache) == [] and leftovers(mp4_cache) == []


def test_the_song_landed_on_after_skipping_doesnt_wait_for_the_ones_skipped(upstream, mp4_cache, monkeypatch):
    """
    The review's case through the real app: Next pressed four times on songs not yet made, each
    request hanging up as the next song is asked for. Only the fifth is made, and it answers in
    about the time one song takes - not after four other downloads and repackages.
    """
    state, _ = upstream
    step = 0.04  # FLAC is 13 chunks: about half a second a download
    bodies = unhurried_navidrome(state, songs={f"song-{n}": FLAC for n in range(1, 6)}, step=step)
    monkeypatch.setattr(download_routes, "DISCONNECT_CHECK_SECONDS", 0.02)
    app = start()
    answers = {n: [] for n in range(1, 6)}

    async def skip_four():
        began = time.monotonic()
        asks = []
        for n in range(1, 6):
            hang_up = 0.1 if n < 5 else None
            asks.append(asyncio.ensure_future(asgi_get(
                app, f"/deadwax/navidrome/stream/song-{n}", "format=raw&wrap=mp4", hang_up, answers[n],
                headers=[(b"range", b"bytes=0-1")])))
            await asyncio.sleep(0.1)
        asked_fifth = began + 0.4
        await asyncio.gather(*asks)
        start_line = next(at for at, message in answers[5] if message["type"] == "http.response.start")
        return start_line - asked_fifth, next(m for _, m in answers[5] if m["type"] == "http.response.start")

    waited, started = asyncio.run(skip_four())

    assert started["status"] == 206 and (b"content-type", b"audio/mp4") in started["headers"]
    assert [path.stem for path in cached(mp4_cache)] == [mp4_cache.path_for(
        mp4_cache._versions["song-5"][1]).stem], "only the song landed on was made"
    for n in range(1, 5):
        [body] = bodies[f"song-{n}"]
        assert body.closed and not body.finished, f"song {n}'s download was let go of"
    one_download = 13 * step
    assert waited < one_download * 2.5, f"song 5 waited {waited:.2f}s - about one download is {one_download:.2f}s"


# ---------------------------------------------------------------- one URL, one file

@pytest.mark.parametrize("header, carries_on", [
    (None, False),
    ("bytes=0-1", False),           # Safari's first two bytes: a song starting
    ("bytes = 0 - 1", False),
    ("bytes=0-", True),             # the rest, after the probe
    ("bytes=2-100", True),
    ("bytes=1000-", True),          # a seek
    ("bytes=-500", True),
    ("bytes=0-1,5-6", False),       # answered whole, so a start
    ("items=0-1", False),
])
def test_what_carries_on_from_bytes_the_phone_already_has(header, carries_on):
    assert continues(header) is carries_on


def test_a_song_sent_as_flac_goes_on_as_flac_for_the_whole_play(upstream, client, mp4_cache):
    """
    The review's first case (review4/test_splice.py): the first download is cut, so the probe is
    answered with the FLAC. Every request carrying on from it gets the FLAC too - a seek minutes
    later included, long after VERSION_SECONDS - and nothing is fetched to be made meanwhile.
    """
    state, _ = upstream
    fake, file_handler = navidrome_file()

    def handle(request):
        if request.headers.get("range"):
            return file_handler(request)
        fake["whole"] += 1
        if fake["whole"] == 1:
            return streamed(200, FLAC, {"content-type": "audio/flac", "last-modified": STAMP},
                            fails=httpx.ReadError("connection reset"), fails_after=8192)
        return streamed(200, FLAC, {"content-type": "audio/flac", "last-modified": STAMP})

    state["handler"] = handle
    probe = client.get(WRAPPED, headers={"Range": "bytes=0-1"})
    rest = client.get(WRAPPED, headers={"Range": "bytes=2-100"})
    later = mp4_cache.clock() + player_cache.VERSION_SECONDS * 10
    mp4_cache.clock = lambda: later
    seek = client.get(WRAPPED, headers={"Range": "bytes=1000-"})

    assert (probe.headers["content-type"], probe.headers["content-range"]) == ("audio/flac", f"bytes 0-1/{len(FLAC)}")
    assert (rest.content, rest.headers["content-range"]) == (FLAC[2:101], f"bytes 2-100/{len(FLAC)}")
    assert (seek.content, seek.headers["content-type"]) == (FLAC[1000:], "audio/flac")
    assert fake["whole"] == 1, "only the cut download - nothing was made while the FLAC was playing"
    assert cached(mp4_cache) == []


def test_an_mp4_that_cant_be_had_again_mid_song_is_a_503_not_flac(upstream, client, mp4_cache, caplog):
    """
    The review's second case: made and served, then cleared out while the song plays, and the
    re-make is cut. The rest of the song gets a 503 - never FLAC bytes under another length - and
    the page's retry, which starts the song afresh, gets the FLAC while Navidrome still can't send
    the file whole.
    """
    state, _ = upstream
    fake, file_handler = navidrome_file()

    def handle(request):
        if request.headers.get("range"):
            return file_handler(request)
        fake["whole"] += 1
        if fake["whole"] >= 2:
            return streamed(200, FLAC, {"content-type": "audio/flac", "last-modified": STAMP},
                            fails=httpx.ReadError("connection reset"), fails_after=8192)
        return streamed(200, FLAC, {"content-type": "audio/flac", "last-modified": STAMP})

    state["handler"] = handle
    probe = client.get(WRAPPED, headers={"Range": "bytes=0-1"})
    for made in cached(mp4_cache):
        made.unlink()
    rest = client.get(WRAPPED, headers={"Range": "bytes=2-100"})
    retried = client.get(WRAPPED, headers={"Range": "bytes=0-1"})
    after_retry = client.get(WRAPPED, headers={"Range": "bytes=2-100"})

    assert (probe.headers["content-type"], probe.headers["content-range"]) == ("audio/mp4", f"bytes 0-1/{len(MP4)}")
    assert rest.status_code == 503
    assert rest.headers["retry-after"] == str(player_cache.RETRY_AFTER_SECONDS)
    assert rest.headers["cache-control"] == "no-store"
    assert "content-range" not in rest.headers
    assert said(caplog, "asked to try again rather than sent the FLAC")
    assert (retried.headers["content-type"], retried.content) == ("audio/flac", FLAC[:2])
    assert (after_retry.headers["content-type"], after_retry.content) == ("audio/flac", FLAC[2:101])


def test_an_mp4_cleared_out_mid_song_is_made_again_and_waited_for(upstream, client, mp4_cache):
    state, _ = upstream
    fake, state["handler"] = navidrome_file()

    client.get(WRAPPED, headers={"Range": "bytes=0-1"})
    for made in cached(mp4_cache):
        made.unlink()
    rest = client.get(WRAPPED, headers={"Range": "bytes=2-100"})

    assert (rest.status_code, rest.headers["content-type"], rest.content) == (206, "audio/mp4", MP4[2:101])
    assert fake["whole"] == 2


def test_an_mp4_cleared_out_between_being_found_and_opened_is_made_again(upstream, client, mp4_cache, monkeypatch):
    """The FileNotFoundError path: found, then gone before it opened - made again, not the FLAC."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file()
    client.get(WRAPPED, headers={"Range": "bytes=0-1"})
    real = player_cache._open_cached
    raced = []

    def cleared_first(path):
        if not raced:
            raced.append(path)
            path.unlink()
        return real(path)

    monkeypatch.setattr(player_cache, "_open_cached", cleared_first)
    rest = client.get(WRAPPED, headers={"Range": "bytes=1000-"})

    assert raced and (rest.status_code, rest.content) == (206, MP4[1000:])
    assert fake["whole"] == 2


# ---------------------------------------------------------------- a disk short of space

def test_a_full_disk_clears_older_songs_and_tries_once_more(upstream, client, mp4_cache, monkeypatch, caplog):
    """
    review4/enospc.py: the disk fills while a song is repackaged. The songs played longest ago go,
    room for two copies of this one, and it is tried again - where it used to send the FLAC and
    keep every MP4 it held for good.
    """
    state, _ = upstream
    fake, state["handler"] = navidrome_file()
    stream = "/deadwax/navidrome/stream/{}?format=raw&wrap=mp4"
    client.get(stream.format("older"))
    [older] = cached(mp4_cache)
    real = player_cache._repackage
    full = []

    def fills_once(part, target):
        if not full:
            full.append(1)
            raise OSError(errno.ENOSPC, "No space left on device")
        return real(part, target)

    monkeypatch.setattr(player_cache, "_repackage", fills_once)
    caplog.set_level(logging.INFO)
    response = client.get(stream.format("newer"))

    assert (response.headers["content-type"], response.content) == ("audio/mp4", MP4)
    assert not older.exists(), "the song played longest ago made room"
    assert len(cached(mp4_cache)) == 1 and leftovers(mp4_cache) == []
    assert said(caplog, "filled up while song newer")


def test_a_disk_that_stays_full_sends_the_flac_and_leaves_nothing(upstream, client, mp4_cache, monkeypatch, caplog):
    state, _ = upstream
    fake, state["handler"] = navidrome_file()

    def always_full(part, target):
        raise OSError(errno.ENOSPC, "No space left on device")

    monkeypatch.setattr(player_cache, "_repackage", always_full)
    response = client.get(WRAPPED)

    assert (response.headers["content-type"], response.content) == ("audio/flac", FLAC)
    assert cached(mp4_cache) == [] and leftovers(mp4_cache) == []
    assert said(caplog, "couldn't be put in an MP4")


Usage = namedtuple("Usage", "total used free")


def a_disk(monkeypatch, cache: Mp4Cache, budget: int):
    """A disk of `budget` bytes holding nothing but the cache folder."""
    def usage(folder):
        held = sum(p.stat().st_size for p in cache.directory.iterdir())
        return Usage(budget, held, budget - held)
    monkeypatch.setattr(player_cache.shutil, "disk_usage", usage)


def test_room_on_the_disk_is_made_before_a_song_is_fetched(upstream, client, mp4_cache, monkeypatch):
    """
    Both copies of the song and DISK_SPARE_BYTES have to fit before anything is written. Short
    until an older song goes: it goes, and the song is made.
    """
    state, _ = upstream
    fake, state["handler"] = navidrome_file()
    stream = "/deadwax/navidrome/stream/{}?format=raw&wrap=mp4"
    client.get(stream.format("older"))
    [older] = cached(mp4_cache)
    a_disk(monkeypatch, mp4_cache, player_cache.DISK_SPARE_BYTES + 2 * len(FLAC) + older.stat().st_size - 1)

    response = client.get(stream.format("newer"))

    assert response.content == MP4
    assert not older.exists()


def test_a_disk_short_even_when_emptied_sends_the_flac_without_fetching(upstream, client, mp4_cache, monkeypatch,
                                                                       caplog):
    """Never written until ENOSPC: short of room, the FLAC goes at once and the disk is left alone."""
    state, _ = upstream
    fake, state["handler"] = navidrome_file()
    a_disk(monkeypatch, mp4_cache, player_cache.DISK_SPARE_BYTES + len(FLAC))

    response = client.get(WRAPPED)

    assert (response.headers["content-type"], response.content) == ("audio/flac", FLAC)
    assert fake["whole"] == 1, "fetched once, for the relay - never to be made"
    assert said(caplog, "is short of space")


def test_songs_being_made_count_against_the_cap(tmp_path):
    """
    Room is made counting the songs being made, so the MP4s never add up to more than the cap;
    and when the songs being made fill it by themselves, another isn't started.
    """
    cache = Mp4Cache(tmp_path / "c", max_bytes=300)
    folder, _ = player_cache._own(cache.directory)
    for age, name in enumerate(("a", "b", "c")):
        path = folder / f"{name}.mp4"
        path.write_bytes(bytes(100))
        os.utime(path, (1000 + age, 1000 + age))

    cache._reserved = 100 + 100  # one song already being made, and this one
    assert cache._make_room(folder, 100)
    assert sorted(p.name for p in folder.glob("*.mp4")) == ["c.mp4"], "the two played longest ago went"

    cache._reserved = 350 + 100  # the songs being made are over the cap by themselves
    assert not cache._make_room(folder, 100)


def test_room_is_made_for_the_song_coming_not_the_size_of_the_songs_cleared(tmp_path):
    """
    A big song after many small ones: the room is judged by the song coming. A loop that judged it
    by each small song as it was about to clear it cleared none, and the cache went 40% past its
    cap until the make had finished.
    """
    cache = Mp4Cache(tmp_path / "c", max_bytes=1000)
    folder, _ = player_cache._own(cache.directory)
    for age in range(10):
        path = folder / f"{age:02d}.mp4"
        path.write_bytes(bytes(90))
        os.utime(path, (1000 + age, 1000 + age))

    cache._reserved = 500
    assert cache._make_room(folder, 500)
    left = sorted(p.name for p in folder.glob("*.mp4"))
    assert left == [f"{age:02d}.mp4" for age in range(5, 10)], "the five played longest ago went"
    assert 90 * len(left) + 500 <= 1000


def test_a_song_bigger_than_whats_left_goes_past_the_cap_by_that_song_alone(tmp_path):
    cache = Mp4Cache(tmp_path / "c", max_bytes=100)
    folder, _ = player_cache._own(cache.directory)
    cache._reserved = 150
    assert cache._make_room(folder, 150), "nothing else is being made: past the cap by this song only"


# ---------------------------------------------------------------- nowhere to keep it

def test_a_read_only_root_filesystem_still_starts(tmp_path):
    """
    review4/ro_app.py: every temporary folder read-only (read_only: true, no tmpfs). Importing the
    player's routes and building the app used to fail on tempfile.gettempdir(); nothing about the
    cache's folder is decided at import now.
    """
    read_only = tmp_path / "ro"
    read_only.mkdir()
    read_only.chmod(0o555)
    script = (
        "import sys, tempfile\n"
        f"sys.path.insert(0, {str(ROOT)!r})\n"
        f"tempfile._candidate_tempdir_list = lambda: [{str(read_only)!r}]\n"
        "tempfile.tempdir = None\n"
        "import src.routes.navidrome\n"
        "from src.api.app import start\n"
        "start()\n"
        "print('built')\n"
    )
    try:
        result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True, timeout=120,
                                cwd=str(read_only))
    finally:
        read_only.chmod(0o755)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip().endswith("built")


def test_no_temporary_space_sends_the_flac_and_says_so_once(upstream, client, monkeypatch, caplog):
    state, _ = upstream
    fake, state["handler"] = navidrome_file()
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", None)
    monkeypatch.setattr(player_cache, "cache", Mp4Cache())

    def nowhere():
        raise FileNotFoundError(errno.ENOENT, "No usable temporary directory found")

    monkeypatch.setattr(player_cache.tempfile, "gettempdir", nowhere)
    first = client.get(WRAPPED)
    second = client.get(WRAPPED, headers={"Range": "bytes=0-1"})

    assert (first.headers["content-type"], first.content) == ("audio/flac", FLAC)
    assert second.headers["content-type"] == "audio/flac"
    told = said(caplog, "the player's cache can't be kept")
    assert len(told) == 1 and "PLAYER_CACHE_PATH" in told[0].getMessage()


def test_a_cache_path_that_cant_be_written_sends_the_flac(upstream, client, tmp_path, monkeypatch, caplog):
    state, _ = upstream
    fake, state["handler"] = navidrome_file()
    shut = tmp_path / "shut"
    shut.mkdir()
    shut.chmod(0o555)
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", str(shut))
    monkeypatch.setattr(player_cache, "cache", Mp4Cache())
    try:
        response = client.get(WRAPPED)
    finally:
        shut.chmod(0o755)

    assert (response.headers["content-type"], response.content) == ("audio/flac", FLAC)
    assert said(caplog, "couldn't be made")
    assert not (shut / FOLDER_NAME).exists()


# ---------------------------------------------------------------- deadwax's own folder

def test_the_folder_is_made_private(upstream, client, mp4_cache):
    state, _ = upstream
    _, state["handler"] = navidrome_file()
    client.get(WRAPPED)
    info = os.lstat(mp4_cache.directory)
    assert stat.S_ISDIR(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o700
    assert info.st_uid == os.getuid()


def test_a_link_in_the_folders_place_is_never_followed(upstream, client, tmp_path, monkeypatch, caplog):
    """
    review4's planted link: someone else's music behind a link where the cache's folder goes. The
    start-up clean-up used to delete an old file in there; now nothing in it is touched or served.
    """
    state, _ = upstream
    fake, state["handler"] = navidrome_file()
    victim = tmp_path / "victim"
    victim.mkdir(mode=0o700)
    song = victim / "01 - Song.flac"
    song.write_bytes(b"not yours")
    old = time.time() - player_cache.LEFTOVER_SECONDS * 2
    os.utime(song, (old, old))
    shared = tmp_path / "shared"
    shared.mkdir()
    (shared / FOLDER_NAME).symlink_to(victim)
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", str(shared))
    monkeypatch.setattr(player_cache, "cache", Mp4Cache())

    response = client.get(WRAPPED)

    assert (response.headers["content-type"], response.content) == ("audio/flac", FLAC)
    assert song.read_bytes() == b"not yours" and sorted(p.name for p in victim.iterdir()) == ["01 - Song.flac"]
    assert said(caplog, "is a link, not a folder deadwax made")


def test_a_folder_open_to_others_is_refused_and_what_was_planted_in_it_never_served(upstream, client, tmp_path,
                                                                                   monkeypatch):
    """
    review4/plant.py: a folder made first, open to anybody, with a link under the next song's key
    to a private file. It used to be served back as the song.
    """
    state, _ = upstream
    fake, state["handler"] = navidrome_file()
    secret = tmp_path / "secret.txt"
    secret.write_text("PRIVATE KEY MATERIAL\n")
    planted = tmp_path / "shared" / FOLDER_NAME
    planted.mkdir(parents=True)
    planted.chmod(0o777)
    #? everything the key needs is in what deadwax relays for the raw stream
    version = player_cache.Version(song_id="song-1", size=len(FLAC), stamp=json.dumps([STAMP, None]))
    (planted / f"{version.key[:40]}.mp4").symlink_to(secret)
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", str(tmp_path / "shared"))
    monkeypatch.setattr(player_cache, "cache", Mp4Cache())

    response = client.get(WRAPPED, headers={"Range": "bytes=0-100"})

    assert response.headers["content-type"] == "audio/flac"
    assert b"PRIVATE" not in response.content
    assert stat.S_IMODE(planted.stat().st_mode) == 0o777, "not deadwax's to change"


def test_a_folder_belonging_to_someone_else_is_refused(upstream, client, tmp_path, monkeypatch, caplog):
    state, _ = upstream
    _, state["handler"] = navidrome_file()
    theirs = tmp_path / "c"
    theirs.mkdir(mode=0o700)
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(theirs))
    real_uid = os.getuid()
    monkeypatch.setattr(player_cache.os, "getuid", lambda: real_uid + 1)

    response = client.get(WRAPPED)

    assert response.headers["content-type"] == "audio/flac"
    assert said(caplog, "belongs to another user")


def test_a_setgid_bit_is_no_bar(upstream, client, tmp_path, monkeypatch):
    """
    OpenMediaVault sets setgid on every shared folder, and Linux's mkdir passes it on: the folder
    deadwax finds there is 02700, which gives nobody else anything. Judging the whole mode refused it
    on every song, and removing it only brought it back the same.
    """
    state, _ = upstream
    _, state["handler"] = navidrome_file()
    shared = tmp_path / "omv-share"
    (shared / FOLDER_NAME).mkdir(parents=True, mode=0o700)
    (shared / FOLDER_NAME).chmod(0o2700)
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", str(shared))
    monkeypatch.setattr(player_cache, "cache", Mp4Cache())

    response = client.get(WRAPPED)

    assert response.headers["content-type"] == "audio/mp4" and response.content == MP4
    assert stat.S_IMODE((shared / FOLDER_NAME).stat().st_mode) == 0o2700, "not made by deadwax this time: left alone"


def test_the_folder_deadwax_makes_under_a_setgid_folder_is_made_private(tmp_path, monkeypatch):
    """Linux's mkdir inherits setgid (macOS's doesn't, so the test makes it happen): deadwax drops it."""
    real_mkdir = os.mkdir

    def linux_mkdir(path, mode=0o777):
        real_mkdir(path, mode)
        os.chmod(path, 0o2000 | mode)

    monkeypatch.setattr(player_cache.os, "mkdir", linux_mkdir)
    folder, problem = player_cache.open_folder(str(tmp_path))
    assert problem is None and folder == tmp_path / FOLDER_NAME
    assert stat.S_IMODE(folder.stat().st_mode) == 0o700


def test_a_disk_that_keeps_no_permissions_says_so(tmp_path, monkeypatch):
    """CIFS, NTFS or exFAT: every folder is 0777 whatever deadwax asks, and removing it never helps."""
    real_mkdir, real_chmod = os.mkdir, os.chmod

    def open_mkdir(path, mode=0o777):
        real_mkdir(path, mode)
        real_chmod(path, 0o777)

    monkeypatch.setattr(player_cache.os, "mkdir", open_mkdir)
    monkeypatch.setattr(player_cache.os, "chmod", lambda path, mode: None)
    folder, problem = player_cache.open_folder(str(tmp_path))
    assert folder is None
    assert "doesn't keep file permissions" in problem and "Linux-formatted disk" in problem


def test_a_shared_cache_path_gets_a_private_folder_of_deadwaxs_own(upstream, client, tmp_path, monkeypatch):
    """
    PLAYER_CACHE_PATH can be a folder other things use: deadwax makes deadwax-player inside it,
    private, and leaves the folder and what else is in it exactly as they were.
    """
    state, _ = upstream
    _, state["handler"] = navidrome_file()
    shared = tmp_path / "ssd-cache"
    shared.mkdir()
    shared.chmod(0o777)
    other = shared / "someone-elses.bin"
    other.write_bytes(b"theirs")
    old = time.time() - player_cache.LEFTOVER_SECONDS * 2
    os.utime(other, (old, old))
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", str(shared))
    monkeypatch.setattr(player_cache, "cache", Mp4Cache())

    response = client.get(WRAPPED)

    assert response.content == MP4
    made = list((shared / FOLDER_NAME).glob("*.mp4"))
    assert len(made) == 1 and stat.S_IMODE((shared / FOLDER_NAME).stat().st_mode) == 0o700
    assert stat.S_IMODE(shared.stat().st_mode) == 0o777 and other.read_bytes() == b"theirs"


# ---------------------------------------------------------------- the two settings

@pytest.fixture
def settings_app(tmp_path, monkeypatch):
    """The real app with a throwaway database, and the settings as the environment left them."""
    monkeypatch.setattr(Config, "PLAYER_CACHE_PATH", None)
    monkeypatch.setattr(Config, "PLAYER_CACHE_MB", "1024")
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ENV_VALUES", {})
    #? the default location, were anything to reach it, is this test's own
    monkeypatch.setattr(tempfile, "tempdir", str(tmp_path / "temporary"))
    (tmp_path / "temporary").mkdir()
    monkeypatch.setattr(player_cache, "cache", Mp4Cache())
    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    app = start()
    app.state.store = store
    return TestClient(app)


def save(app: TestClient, **values) -> httpx.Response:
    return app.put("/deadwax/settings", json=[{"key": key, "value": value} for key, value in values.items()])


def row(payload: dict, key: str) -> tuple[str, dict]:
    for group in payload["groups"]:
        for setting in group["settings"]:
            if setting["key"] == key:
                return group["id"], setting
    raise AssertionError(f"{key} is not in the settings payload")


def test_a_cache_path_saved_in_the_tab_is_used_without_a_restart(upstream, settings_app, tmp_path):
    state, _ = upstream
    _, state["handler"] = navidrome_file()
    ssd = tmp_path / "ssd"
    ssd.mkdir()

    saved = save(settings_app, PLAYER_CACHE_PATH=str(ssd))
    response = settings_app.get(WRAPPED)

    assert saved.status_code == 200
    group, setting = row(saved.json(), "PLAYER_CACHE_PATH")
    assert (group, setting["value"], setting["status"], setting["overridden"]) == ("paths", str(ssd), "ok", True)
    assert str(ssd / FOLDER_NAME) in setting["effect"]
    assert response.content == MP4
    assert len(list((ssd / FOLDER_NAME).glob("*.mp4"))) == 1
    assert not (tmp_path / "temporary" / FOLDER_NAME).exists(), "nothing went to the temporary space"

    reverted = save(settings_app, PLAYER_CACHE_PATH=None)
    _, setting = row(reverted.json(), "PLAYER_CACHE_PATH")
    assert (setting["value"], setting["status"], setting["overridden"]) == (None, "unset", False)
    assert "temporary space" in setting["effect"]
    other = settings_app.get("/deadwax/navidrome/stream/song-2?format=raw&wrap=mp4")
    assert other.content == MP4
    assert len(list((tmp_path / "temporary" / FOLDER_NAME).glob("*.mp4"))) == 1, "and back where it was"


@pytest.mark.parametrize("value", ["abc", "63", "1048577", "1.5", "", " ", "-5", "1_024", "٣٣٣"])
def test_a_cache_size_that_isnt_one_is_refused(settings_app, value):
    response = save(settings_app, PLAYER_CACHE_MB=value)
    assert response.status_code == 400
    assert "PLAYER_CACHE_MB: expected a whole number of MB, 64 to 1048576" in response.json()["detail"]


def test_a_cache_size_saved_in_the_tab_is_the_cap_at_once(settings_app, upstream, tmp_path):
    saved = save(settings_app, PLAYER_CACHE_MB="2048")

    assert saved.status_code == 200
    group, setting = row(saved.json(), "PLAYER_CACHE_MB")
    assert (group, setting["value"], setting["status"], setting["overridden"]) == ("paths", "2048", "ok", True)
    assert "at most 2048 MB" in setting["effect"]
    assert player_cache.cache.max_bytes == 2048 << 20 == player_cache_bytes()

    assert save(settings_app, PLAYER_CACHE_MB="64 MB").status_code == 200, "the unit may be typed"
    assert player_cache.cache.max_bytes == 64 << 20


def test_a_cache_size_from_the_environment_that_isnt_one_is_the_default_and_says_so(settings_app, monkeypatch):
    monkeypatch.setattr(Config, "PLAYER_CACHE_MB", "lots")
    _, setting = row(settings_app.get("/deadwax/settings").json(), "PLAYER_CACHE_MB")
    assert setting["status"] == "error" and setting["detail"] == "expected a whole number of MB, 64 to 1048576"
    assert setting["effect"].startswith("unrecognised, so 1024 is used")
    assert player_cache.cache.max_bytes == 1024 << 20


def test_the_paths_row_says_what_is_wrong_with_the_folder(settings_app, tmp_path, monkeypatch):
    """Stored and reported, like any path - a volume may be about to be mounted - with the reason."""
    missing = tmp_path / "not-mounted"
    assert save(settings_app, PLAYER_CACHE_PATH=str(missing)).status_code == 200
    _, setting = row(settings_app.get("/deadwax/settings").json(), "PLAYER_CACHE_PATH")
    assert setting["status"] == "error" and "nothing exists" in setting["detail"]

    shut = tmp_path / "shut"
    shut.mkdir()
    shut.chmod(0o555)
    try:
        save(settings_app, PLAYER_CACHE_PATH=str(shut))
        _, setting = row(settings_app.get("/deadwax/settings").json(), "PLAYER_CACHE_PATH")
    finally:
        shut.chmod(0o755)
    assert setting["status"] == "error"
    assert "NOT writable, so the player can't keep its MP4s there and Safari is sent FLAC" in setting["detail"]

    linked = tmp_path / "linked"
    linked.mkdir()
    (linked / FOLDER_NAME).symlink_to(tmp_path)
    save(settings_app, PLAYER_CACHE_PATH=str(linked))
    _, setting = row(settings_app.get("/deadwax/settings").json(), "PLAYER_CACHE_PATH")
    assert setting["status"] == "error" and "is a link" in setting["detail"]
    assert "Safari is sent FLAC" in setting["detail"]


def test_the_settings_page_looks_without_making_anything(settings_app, tmp_path):
    fresh = tmp_path / "fresh"
    fresh.mkdir()
    save(settings_app, PLAYER_CACHE_PATH=str(fresh))
    _, setting = row(settings_app.get("/deadwax/settings").json(), "PLAYER_CACHE_PATH")
    assert setting["status"] == "ok"
    assert not (fresh / FOLDER_NAME).exists(), "made on first use, not by being looked at"


def test_the_cache_size_is_read_as_a_whole_number_of_megabytes():
    assert [parse_player_cache_mb(v) for v in ("1024", " 64 ", "1048576", "512MB", "512 mb")] == [
        1024, 64, 1048576, 512, 512]
    assert [parse_player_cache_mb(v) for v in (None, "", "63", "1048577", "1e3", "0x40", "+64")] == [
        None] * 7
