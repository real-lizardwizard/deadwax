"""
The player's "Up to 48 kHz" through the real app (1.1.0-player.6): the stream route's `max_rate`,
and the cache keeping a resampled song as a variant of its own - its own file, ETag, make, refusal,
pin and memory of what its URL was answered as - with every answer of it saying so.

And the promise the whole thing rests on, end to end: an album of three hi-res songs cut from one
piece of music at awkward places, each fetched from the route as the gapless player fetches it - a
resampled fragmented MP4 - and decoded, joins into exactly what one resample of the whole album
gives, within the one LSB of 24-bit rounding. Without its album around it, the same album clicks at
the joins.

Navidrome is test_album_context.py's fake album, behind test_navidrome.py's fake client, and deadwax
is start()'s app, middleware and all. Anything that resamples needs numpy, soxr and soundfile, and
skips without them - never in CI (see test_resample.py). What doesn't resample runs anywhere.
"""

import asyncio
import errno
import io
import logging
import re
import struct
import sys
import threading
import time
from pathlib import Path

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import album_context, player_cache, resample  # noqa: E402
from src.api.app import start  # noqa: E402
from src.flac_mp4 import flac_to_fmp4, flac_to_mp4  # noqa: E402
from src.player_cache import Mp4Cache  # noqa: E402
from src.routes import download as download_routes  # noqa: E402
import test_navidrome as navidrome_tests  # noqa: E402
from test_album_context import LATER, AlbumNavidrome, hires, later, plan_of, serving  # noqa: E402
from test_navidrome import FLAC, HEAD, fragmented, plain  # noqa: E402
from test_player_cache import Probe, a_disk, body_of, leftovers, navidrome_goes_down, played_long_ago  # noqa: E402
from test_resample import (BOTTOM, FULL, GAIN, TOP, ADiskThatFills, constant_flac, continuous, floats,  # noqa: E402
                          libraries, music, overshoot, square, write_flac)

#? test_navidrome.py's fake Navidrome client, the real app, and a cache of the test's own
configured, upstream, client, mp4_cache = (navidrome_tests.configured, navidrome_tests.upstream,
                                           navidrome_tests.client, navidrome_tests.mp4_cache)

CAPPED = "&max_rate=48000"


def stream(song: str, wrap: str = "fmp4", capped: bool = True) -> str:
    return f"/deadwax/navidrome/stream/{song}?format=raw&wrap={wrap}" + (CAPPED if capped else "")


def flac_inside(mp4: bytes) -> bytes:
    """The FLAC an MP4 or a fragmented MP4 carries: its STREAMINFO out of the dfLa box, and every mdat
    body in order - the frames, untouched."""
    at = mp4.find(b"dfLa")
    info = mp4[at + 12:at + 46]
    bodies, pos = [], 0
    while pos < len(mp4):
        size, kind = struct.unpack(">I4s", mp4[pos:pos + 8])
        if kind == b"mdat":
            bodies.append(mp4[pos + 8:pos + size])
        pos += size
    return b"fLaC" + bytes((0x80, 0, 0, 34)) + info + b"".join(bodies)


def streaminfo_in(mp4: bytes) -> tuple[int, int, int, int]:
    """(rate, bits, channels, samples) as the dfLa box says - what the page's head gate reads."""
    at = mp4.find(b"dfLa")
    packed = int.from_bytes(mp4[at + 22:at + 30], "big")
    return packed >> 44, ((packed >> 36) & 0x1F) + 1, ((packed >> 41) & 0x7) + 1, packed & 0xFFFFFFFFF


def decoded(sf, mp4: bytes):
    samples, rate = sf.read(io.BytesIO(flac_inside(mp4)), dtype="int32", always_2d=True)
    return samples >> 8, rate


def cut(np, sf, tmp_path: Path, samples, lengths, rate: int = 192000) -> dict[str, bytes]:
    """An album of songs cut from `samples` at `lengths`, as 24-bit FLACs: song-1, song-2..."""
    files, at = {}, 0
    for i, n in enumerate(lengths):
        files[f"song-{i + 1}"] = write_flac(sf, tmp_path / f"song-{i + 1}.flac", samples[at:at + n], rate).read_bytes()
        at += n
    return files


#? splits that aren't multiples of 4: at 96001 (1 past one) and 160003 (3 past one)
LENGTHS = (96001, 64002, 96000)


def an_album(np, sf, tmp_path: Path):
    samples = music(np, 192000, sum(LENGTHS), level=0.5)
    return samples, cut(np, sf, tmp_path, samples, LENGTHS)


def said(caplog, words: str) -> list[str]:
    return [record.getMessage() for record in caplog.records if words in record.getMessage()]


# ---------------------------------------------------------------- the route

@pytest.mark.parametrize("query", ["format=mp3&wrap=mp4", "format=raw", "format=mp3", "wrap=fmp4", ""],
                         ids=["a transcode in an MP4", "no wrap", "a transcode", "no format", "nothing"])
def test_max_rate_needs_the_file_as_it_is_and_a_wrap(upstream, client, query):
    """Only a FLAC deadwax repackages can be resampled; the file relayed as it is, or a transcode,
    can't - a 400 saying so, with Navidrome never asked."""
    state, seen = upstream
    response = client.get(f"/deadwax/navidrome/stream/song-1?{query}{CAPPED}")
    assert response.status_code == 400
    assert response.json()["detail"].startswith("max_rate needs format=raw and wrap=mp4 or wrap=fmp4")
    assert seen == []


@pytest.mark.parametrize("value", ["44100", "original", "", "48000.0", "96000"])
def test_any_other_max_rate_is_refused(upstream, client, value):
    state, seen = upstream
    response = client.get(f"/deadwax/navidrome/stream/song-1?format=raw&wrap=fmp4&max_rate={value}")
    assert response.status_code == 422
    assert seen == []


# ---------------------------------------------------------------- songs it doesn't touch

@pytest.mark.parametrize("song", [FLAC, constant_flac(bps=20), constant_flac(bps=32)],
                         ids=["44.1 kHz", "192 kHz 20-bit", "192 kHz 32-bit"])
@pytest.mark.parametrize("wrap", ["mp4", "fmp4"])
def test_a_song_the_cap_doesnt_touch_is_answered_from_the_very_same_file(upstream, client, song, wrap):
    """The same bytes and the same ETag as without max_rate, no header, and nothing asked of its
    album - one make, shared by both URLs."""
    state, _ = upstream
    album = serving(state, {"song": song})

    plain = client.get(stream("song", wrap, capped=False), headers={"Range": HEAD})
    capped = client.get(stream("song", wrap), headers={"Range": HEAD})

    assert plain.headers["content-type"] == "audio/mp4"
    assert (capped.status_code, capped.content, capped.headers["etag"]) == (
        plain.status_code, plain.content, plain.headers["etag"])
    assert "x-deadwax-resampled" not in capped.headers
    assert album.calls == []
    assert album.whole["song"] == 1


def test_without_the_audio_libraries_max_rate_is_ignored_and_said_once(upstream, client, mp4_cache, monkeypatch,
                                                                     caplog):
    """A deadwax run without numpy, soxr or soundfile starts and plays as ever: a request asking for
    a song resampled gets the song as it is - its URL remembered as the plain one's - and the log
    says why, once."""
    monkeypatch.setattr(player_cache.resample, "missing_libraries", lambda: "numpy, soxr")
    state, _ = upstream
    song = hires((4096,) * 6 + (9,))
    album = serving(state, {"song": song})

    for wrap, made in (("fmp4", flac_to_fmp4), ("mp4", flac_to_mp4)):
        plain = client.get(stream("song", wrap, capped=False), headers={"Range": HEAD})
        capped = [client.get(stream("song", wrap), headers={"Range": HEAD}) for _ in range(2)]
        assert plain.content == made(song)
        for answer in capped:
            assert (answer.content, answer.headers["etag"]) == (plain.content, plain.headers["etag"])
            assert "x-deadwax-resampled" not in answer.headers

    assert len(said(caplog, "can't be resampled on this server - numpy, soxr couldn't be loaded")) == 1
    assert list(mp4_cache._pinned) == ["song"] and list(mp4_cache._answered) == ["song"]
    assert album.calls == []


# ---------------------------------------------------------------- a song resampled

def test_a_hi_res_song_is_streamed_resampled_to_48_khz(upstream, client, mp4_cache, tmp_path):
    """
    The gapless player's request for a 192 kHz song: a fragmented MP4 of 48 kHz / 24-bit FLAC, byte
    ranges, If-Range, a 416 past the end - every answer saying `X-Deadwax-Resampled: 192000-48000`.
    The same song asked for as it is stays the original's fragmented MP4: two files, two ETags, two
    makes.
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)

    head = client.get(stream("song-2"), headers={"Range": HEAD})
    assert head.status_code == 206 and head.headers["content-type"] == "audio/mp4"
    assert head.headers["x-deadwax-resampled"] == "192000-48000"
    size = int(head.headers["content-range"].rsplit("/", 1)[1])
    assert size == len(head.content) < 262144
    rate, bits, channels, samples = streaminfo_in(head.content)
    assert (rate, bits, channels) == (48000, 24, 2)
    assert samples == resample.output_count(LENGTHS[1], resample.album_phase(LENGTHS[0], 4), 4)
    etag = head.headers["etag"]

    piece = client.get(stream("song-2"), headers={"Range": "bytes=1000-4999", "If-Range": etag})
    assert (piece.status_code, piece.content) == (206, head.content[1000:5000])
    assert piece.headers["x-deadwax-resampled"] == "192000-48000"
    past = client.get(stream("song-2"), headers={"Range": f"bytes={size}-"})
    assert past.status_code == 416 and past.headers["x-deadwax-resampled"] == "192000-48000"
    stale = client.get(stream("song-2"), headers={"Range": "bytes=1000-4999", "If-Range": '"another"'})
    assert (stale.status_code, stale.content) == (200, head.content)

    #? whole: the original at 192 kHz is bigger than the head fetch
    plain = client.get(stream("song-2", capped=False))
    assert plain.content == flac_to_fmp4(files["song-2"]) and plain.headers["etag"] != etag
    assert "x-deadwax-resampled" not in plain.headers
    assert album.whole["song-2"] == 2 and len(fragmented(mp4_cache)) == 2
    assert leftovers(mp4_cache) == [], "the download and the resampled FLAC gone"


def test_the_url_way_gets_a_resampled_mp4_with_the_header_on_every_answer(upstream, client, tmp_path):
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)

    probe = client.get(stream("song-1", "mp4"), headers={"Range": "bytes=0-1"})
    whole = client.get(stream("song-1", "mp4"))
    past = client.get(stream("song-1", "mp4"), headers={"Range": f"bytes={len(whole.content)}-"})

    assert (probe.status_code, probe.content) == (206, whole.content[:2])
    for answer in (probe, whole, past):
        assert answer.headers["x-deadwax-resampled"] == "192000-48000"
    assert whole.headers["content-type"] == "audio/mp4" and past.status_code == 416
    samples, rate = decoded(sf, whole.content)
    assert rate == 48000 and len(samples) == resample.output_count(LENGTHS[0], 0, 4)
    plain = client.get(stream("song-1", "mp4", capped=False))
    assert plain.content == flac_to_mp4(files["song-1"]) and "x-deadwax-resampled" not in plain.headers


def test_a_song_too_big_to_hold_as_it_is_is_judged_by_what_it_resamples_to(upstream, client, monkeypatch,
                                                                            tmp_path):
    """The memory cap on repackaging bounds the FLAC held, which for a resampled song is the 48 kHz
    one - the source is only ever read from disk a block at a time. A long 24/192 track passes 512 MiB
    at about twenty minutes; resampled it is a quarter of that."""
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / "small", wrap_max_bytes=len(files["song-1"]) // 2))

    capped = client.get(stream("song-1"), headers={"Range": HEAD})
    plain = client.get(stream("song-1", capped=False), headers={"Range": HEAD})

    assert capped.status_code == 206 and capped.headers["x-deadwax-resampled"] == "192000-48000"
    assert plain.status_code == 415 and "held in memory" in plain.json()["detail"]


# ---------------------------------------------------------------- variants never mix

def test_a_song_that_cant_be_resampled_is_sent_as_it_is_and_said_once(upstream, client, mp4_cache, monkeypatch,
                                                                     caplog):
    """The URL way gets the FLAC as it is, the stream a 415 saying why - each refusal said once and
    remembered under the resampled key only: the song asked for as it is goes on as ever."""
    libraries()
    state, _ = upstream
    song = hires((4096,) * 6 + (9,))
    serving(state, {"song": song})

    def refuse(*args, **kwargs):
        raise resample.CannotResample("libsndfile can't read it: a test")

    monkeypatch.setattr(player_cache.resample, "resample_file", refuse)
    flac = [client.get(stream("song", "mp4"), headers={"Range": "bytes=0-1"}) for _ in range(2)]
    refused = [client.get(stream("song"), headers={"Range": HEAD}) for _ in range(2)]
    mp4 = client.get(stream("song", "mp4", capped=False), headers={"Range": "bytes=0-1"})
    fmp4 = client.get(stream("song", capped=False), headers={"Range": HEAD})

    for answer in flac:
        assert (answer.status_code, answer.headers["content-type"], answer.content) == (206, "audio/flac", song[:2])
        assert "x-deadwax-resampled" not in answer.headers
    for answer in refused:
        assert answer.status_code == 415 and "couldn't be resampled exactly" in answer.json()["detail"]
    assert (mp4.headers["content-type"], fmp4.status_code, fmp4.content) == ("audio/mp4", 206, flac_to_fmp4(song))
    assert len(said(caplog, "is sent as the FLAC it is, not resampled to 48 kHz in an MP4")) == 1
    assert len(said(caplog, "isn't streamed by the gapless player resampled to 48 kHz")) == 1
    assert mp4_cache._answered[("song", 48000)][0] == player_cache.FLAC
    assert mp4_cache._answered["song"][0] == player_cache.MP4, "the FLAC answer never reached the plain URL"


def test_a_pin_is_only_ever_for_the_url_it_was_served_under(upstream, client, mp4_cache, tmp_path):
    """An If-Range naming the resampled file, sent to the plain URL, is the plain URL's ordinary way -
    the whole original, never the resampled bytes - and the other way round. With Navidrome down,
    each pin still answers its own URL, header and all."""
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    resampled = client.get(stream("song-1"))
    plain = client.get(stream("song-1", capped=False))

    across = client.get(stream("song-1", capped=False),
                        headers={"Range": "bytes=1000-1999", "If-Range": resampled.headers["etag"]})
    back = client.get(stream("song-1"), headers={"Range": "bytes=1000-1999", "If-Range": plain.headers["etag"]})

    assert (across.status_code, across.content) == (200, plain.content)
    assert "x-deadwax-resampled" not in across.headers
    assert (back.status_code, back.content) == (200, resampled.content)
    assert set(mp4_cache._pinned) == {"song-1", ("song-1", 48000)}

    navidrome_goes_down(state)
    later(mp4_cache, player_cache.VERSION_SECONDS * 10)
    pinned = client.get(stream("song-1"), headers={"Range": "bytes=1000-1999", "If-Range": resampled.headers["etag"]})
    assert (pinned.status_code, pinned.content) == (206, resampled.content[1000:2000])
    assert pinned.headers["x-deadwax-resampled"] == "192000-48000"
    crossed = client.get(stream("song-1", capped=False),
                         headers={"Range": "bytes=1000-1999", "If-Range": resampled.headers["etag"]})
    assert crossed.status_code == 502, "the ordinary way, which asks Navidrome"


# ---------------------------------------------------------------- the plan in the key

def test_a_neighbour_retagged_makes_the_song_again_once_it_is_looked_at_again(upstream, client, tmp_path):
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    first = client.get(stream("song-2"), headers={"Range": HEAD})

    album.modified["song-1"] = LATER
    soon = client.get(stream("song-2"), headers={"Range": HEAD})
    later(player_cache.cache)
    then = client.get(stream("song-2"), headers={"Range": HEAD})

    assert soon.headers["etag"] == first.headers["etag"]
    assert then.headers["etag"] != first.headers["etag"]
    assert album.whole["song-2"] == 2


def test_a_plan_is_kept_across_a_navidrome_hiccup_so_the_song_isnt_made_again(upstream, client, tmp_path, caplog):
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    caplog.set_level(logging.INFO)
    first = client.get(stream("song-2"), headers={"Range": HEAD})

    later(player_cache.cache)
    album.failing.update({"getSong", "getAlbum"})
    again = client.get(stream("song-2"), headers={"Range": HEAD})

    assert again.headers["etag"] == first.headers["etag"] and again.content == first.content
    assert album.whole["song-2"] == 1, "not made a second time"
    assert said(caplog, "resampled as it was last time")


def test_without_its_album_a_song_is_resampled_alone_and_said_once(upstream, client, tmp_path, caplog):
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    album.failing.add("getAlbum")

    first = client.get(stream("song-2"), headers={"Range": HEAD})
    again = client.get(stream("song-2"), headers={"Range": "bytes=100-199", "If-Range": first.headers["etag"]})
    fresh = client.get(stream("song-2"), headers={"Range": HEAD})

    assert first.status_code == 206 and first.headers["x-deadwax-resampled"] == "192000-48000"
    assert streaminfo_in(first.content)[3] == resample.output_count(LENGTHS[1], 0, 4), "phase 0: its own grid"
    assert again.status_code == 206 and fresh.headers["etag"] == first.headers["etag"]
    assert len(said(caplog, "resampled without its album around it")) == 1
    assert album.whole["song-2"] == 1


def test_the_url_way_carries_on_from_the_file_it_has_been_reading(upstream, client, tmp_path):
    """
    Safari sends no If-Range. A song beside the one playing retagged mid-song makes a new plan, so a
    new file of another length - and Safari's next range must still come from the file it has been
    reading. The next time the song starts afresh, it gets the new one.
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    probe = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})
    whole = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-"})

    album.modified["song-3"] = LATER
    later(player_cache.cache)
    seek = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=5000-"})
    fresh = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})

    assert whole.headers["etag"] == probe.headers["etag"]
    assert (seek.status_code, seek.content, seek.headers["etag"]) == (206, whole.content[5000:], probe.headers["etag"])
    assert seek.headers["x-deadwax-resampled"] == "192000-48000"
    assert fresh.headers["etag"] != probe.headers["etag"]


def reads_fail(album: AlbumNavidrome, song: str, how, times: int = 1_000_000) -> None:
    """`song`'s context reads - ranges that don't start at its first byte - fail `times` times,
    raising `how` or answering with it: Navidrome slow or busy for a moment. Its version and its
    STREAMINFO, read from its first bytes, still answer, so the plan honestly names it."""
    real = album.serve
    left = {"times": times}

    def serve(asked: str, request: httpx.Request) -> httpx.Response:
        wanted = request.headers.get("range") or ""
        if asked == song and wanted and not wanted.startswith("bytes=0-") and left["times"] > 0:
            left["times"] -= 1
            if isinstance(how, Exception):
                raise how
            return httpx.Response(how, text="boom")
        return real(asked, request)

    album.serve = serve


@pytest.mark.parametrize("wrap", ["mp4", "fmp4"])
@pytest.mark.parametrize("neighbour, how", [("song-1", 500), ("song-3", httpx.ReadTimeout("a slow NAS"))],
                         ids=["the song before, a 500", "the song after, a timeout"])
def test_a_context_read_that_fails_just_now_is_kept_under_the_plan_it_really_had(upstream, client, mp4_cache,
                                                                                 monkeypatch, tmp_path, wrap,
                                                                                 neighbour, how):
    """
    A neighbour's read fails once while the song is made: it is resampled against silence on that
    side, and played that way - the rest of that play comes from that file, under its own ETag. It is
    kept under the plan without that neighbour, which is what its bytes are, so the next play, with
    Navidrome fine again, makes the song with the context: the exact join, under another ETag. Kept
    under the plan's own key, it was served for good, clicking at that join, and a make of it later
    was other bytes under the same ETag - a splice for anybody holding the first. Each ETag, one set
    of bytes: made again after a restart, it is the same file.
    """
    np, sf, soxr = libraries()
    samples, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    reference = continuous(np, soxr, samples, 192000, 48000)
    one, _ = decoded(sf, client.get(stream("song-1", wrap)).content)
    reads_fail(album, neighbour, how, times=1)

    degraded = client.get(stream("song-2", wrap))
    half = len(degraded.content) // 2
    rest = client.get(stream("song-2", wrap), headers={"Range": f"bytes={half}-", "If-Range": degraded.headers["etag"]})
    later(mp4_cache, player_cache.LOST_SECONDS + 1)
    again = client.get(stream("song-2", wrap))
    made = album.whole["song-2"]
    two, _ = decoded(sf, again.content)
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / "after-a-restart"))
    remade = client.get(stream("song-2", wrap))

    assert (rest.status_code, rest.content) == (206, degraded.content[half:]), "the play carries on from its file"
    lost, _ = decoded(sf, degraded.content)
    join = slice(0, 100) if neighbour == "song-1" else slice(len(lost) - 100, len(lost))
    assert np.abs(lost[join] - reference[len(one):len(one) + len(lost)][join]).max() > 1000, "that join clicked"
    assert again.headers["etag"] != degraded.headers["etag"] and made == 2
    assert np.abs(two - reference[len(one):len(one) + len(two)]).max() <= 1, "made again, exact"
    assert (remade.headers["etag"], remade.content) == (again.headers["etag"], again.content)


def test_a_neighbour_that_still_cant_be_read_costs_no_second_download(upstream, client, mp4_cache, tmp_path):
    """A neighbour that fails every time: a fresh start once VERSION_SECONDS have passed asks for its
    samples again - that is the point - and finds the file made without them, making nothing."""
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    reads_fail(album, "song-1", 500)

    first = client.get(stream("song-2"))
    later(mp4_cache, player_cache.VERSION_SECONDS * 5)
    fresh = client.get(stream("song-2"))

    assert (fresh.headers["etag"], fresh.content) == (first.headers["etag"], first.content)
    assert album.whole["song-2"] == 1 and len(fragmented(mp4_cache)) == 1


def context_reads(album: AlbumNavidrome, song: str) -> dict[str, int]:
    """How many times `song`'s context is read from here on - ranges that don't start at its first
    byte - counted whether they answer or not."""
    real, count = album.serve, {"reads": 0}

    def serve(asked: str, request: httpx.Request) -> httpx.Response:
        wanted = request.headers.get("range") or ""
        if asked == song and wanted and not wanted.startswith("bytes=0-"):
            count["reads"] += 1
        return real(asked, request)

    album.serve = serve
    return count


def test_every_fresh_start_soon_after_a_make_that_lost_a_side_is_that_file(upstream, client, mp4_cache, tmp_path):
    """
    Safari with gapless on, the next song too long to hold in memory: the standby is handed its
    address and loads it - its probe, then the rest - and that make meets a hiccup reading the song
    before, so it is made without it. At the handover a few seconds later, Navidrome fine again, the
    readout's probe is a fresh start, and then the element, carrying on, asks for a range. The probe
    had the song made again with the song before, and the element's range was served from that file
    at the first one's offsets - another length, a decode error. For LOST_SECONDS every fresh start
    is the file made without it, asking nothing of the song before; after that a play asks again,
    and is the song made with it.
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-1", "mp4"))
    reads_fail(album, "song-1", 500, times=1)
    reads = context_reads(album, "song-1")
    url = stream("song-2", "mp4")

    probe = client.get(url, headers={"Range": "bytes=0-1"})
    rest = client.get(url, headers={"Range": "bytes=2-"})
    later(mp4_cache, 5)
    readout = client.get(url, headers={"Range": "bytes=0-1"})
    seek = client.get(url, headers={"Range": "bytes=5000-5999"})
    asked = reads["reads"]

    assert readout.headers["etag"] == probe.headers["etag"] == seek.headers["etag"]
    assert readout.headers["content-range"] == probe.headers["content-range"]
    assert (seek.status_code, seek.content) == (206, rest.content[4998:5998]), "the bytes of the file it began on"
    assert asked == 1, "the song before asked for once, by the make"
    assert album.whole["song-2"] == 1

    later(mp4_cache, player_cache.LOST_SECONDS + 1)
    fresh = client.get(url, headers={"Range": "bytes=0-1"})
    assert fresh.headers["etag"] != probe.headers["etag"] and reads["reads"] > asked, "asked for again, and had"
    assert album.whole["song-2"] == 2


def test_a_phone_streaming_the_file_made_without_a_side_carries_on_from_it(upstream, client, mp4_cache, tmp_path):
    """
    The gapless stream the same way. Another phone starting the song in the next LOST_SECONDS gets
    the same file; one starting it after that, the song made with the song before - a file of its
    own - and the first phone's next piece, naming its file in If-Range, still comes from that file:
    not the whole of the other, which the page takes for the song having changed under it.
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-1"))
    reads_fail(album, "song-1", 500, times=1)

    first = client.get(stream("song-2"))
    later(mp4_cache, 5)
    soon = client.get(stream("song-2"), headers={"Range": "bytes=0-999"})
    later(mp4_cache, player_cache.LOST_SECONDS + 1)
    other = client.get(stream("song-2"))
    piece = client.get(stream("song-2"), headers={"Range": "bytes=1000-1999", "If-Range": first.headers["etag"]})
    theirs = client.get(stream("song-2"), headers={"Range": "bytes=1000-1999", "If-Range": other.headers["etag"]})

    assert (soon.headers["etag"], soon.content) == (first.headers["etag"], first.content[:1000])
    assert other.headers["etag"] != first.headers["etag"] and album.whole["song-2"] == 2
    assert (piece.status_code, piece.headers["etag"], piece.content) == (206, first.headers["etag"],
                                                                          first.content[1000:2000])
    assert (theirs.status_code, theirs.headers["etag"], theirs.content) == (206, other.headers["etag"],
                                                                             other.content[1000:2000])


def test_a_neighbour_whose_reads_run_out_of_time_costs_one_wait_in_a_while(upstream, client, mp4_cache, monkeypatch,
                                                                          tmp_path, caplog):
    """
    A neighbour whose range reads never answer in time - its file on a slow or failing mount. Every
    fresh start of the song beside it waited CONTEXT_SECONDS for them before finding the file made
    without them: Safari's probe, the readout's, Chromium's `bytes=0-`, the element at a song change.
    One wait now, and every fresh start in the next LOST_SECONDS is that file at once - made again
    by the plan it had, without that side, if it is cleared out meanwhile; once they have passed, the
    next asks again, and waits once again.
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-1", "mp4"))
    monkeypatch.setattr(album_context, "CONTEXT_SECONDS", 0.5)
    reads = {"song-1": 0}

    async def handle(request):
        wanted = request.headers.get("range") or ""
        if request.url.params.get("id") == "song-1" and wanted and not wanted.startswith("bytes=0-"):
            reads["song-1"] += 1
            await asyncio.sleep(3)
        return album.handle(request)

    state["handler"] = handle
    caplog.set_level(logging.INFO)

    def fresh_start() -> tuple[float, str]:
        began = time.monotonic()
        answer = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})
        assert answer.headers["content-type"] == "audio/mp4"
        return time.monotonic() - began, answer.headers["etag"]

    waits, etags = [], set()
    for _ in range(4):
        took, etag = fresh_start()
        waits.append(took)
        etags.add(etag)
        later(mp4_cache, 5)
    [file] = [path for path in plain(mp4_cache) if path.name.startswith(etag.strip('"'))]
    file.unlink()
    _, etag = fresh_start()
    etags.add(etag)
    asked = reads["song-1"]
    lines = len(said(caplog, "resampled without the song before it"))

    assert waits[0] >= album_context.CONTEXT_SECONDS
    assert max(waits[1:]) < album_context.CONTEXT_SECONDS, f"only the first waited: {waits}"
    assert (asked, lines, len(etags)) == (1, 1, 1), "made again without asking the song before, the same file"
    assert album.whole["song-2"] == 2, "cleared out, and made again once"

    later(mp4_cache, player_cache.LOST_SECONDS + 1)
    took, etag = fresh_start()
    assert took >= album_context.CONTEXT_SECONDS, "asked again once they had passed"
    assert reads["song-1"] == 2 and etags == {etag}
    assert album.whole["song-2"] == 2, "still the file made without it: nothing made again"


def test_a_song_got_ready_minutes_ahead_carries_on_from_the_file_it_began_on(upstream, client, mp4_cache, tmp_path):
    """
    The standby (Safari, the Gapless switch on) asks for the next song 3 s into the song before and
    buffers part of it; the handover comes when that song ends, minutes later. The song before's
    edge couldn't be read at the first ask, so the file was made without it. At the handover the
    readout asks from byte 0 - a fresh start - and the edge reads fine by then: remembered only for
    VERSION_SECONDS, the song was made again with it, and the element carrying on was served the new
    file's bytes at the first one's offsets. Remembered for LOST_SECONDS, which outlasts a song got
    ready ahead of its turn, the whole play is one file. (The re-check's reproduction, at its real
    spacing.)
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-1", "mp4"))
    reads_fail(album, "song-1", 500, times=1)
    url = stream("song-2", "mp4")
    probe = client.get(url, headers={"Range": "bytes=0-1"})
    client.get(url, headers={"Range": "bytes=2-40000"})
    later(mp4_cache, 240)
    readout = client.get(url, headers={"Range": "bytes=0-1"})
    carrying_on = client.get(url, headers={"Range": "bytes=40001-45000"})

    assert readout.headers["etag"] == carrying_on.headers["etag"] == probe.headers["etag"]
    assert album.whole["song-2"] == 1, "made once"


def test_a_slow_neighbour_costs_a_warm_up_one_wait_not_the_song_change_another(upstream, client, mp4_cache,
                                                                               monkeypatch, tmp_path):
    """With the Gapless switch off, the warm-up asks for the next song 3 s into the song before, and
    the element asks again at the song change, minutes later. A neighbour whose reads never answer in
    time cost the warm-up its wait - and, remembered only for VERSION_SECONDS, the song change the
    same wait again. Now the song change finds the file at once."""
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-1", "mp4"))
    monkeypatch.setattr(album_context, "CONTEXT_SECONDS", 0.5)

    async def handle(request):
        wanted = request.headers.get("range") or ""
        if request.url.params.get("id") == "song-1" and wanted and not wanted.startswith("bytes=0-"):
            await asyncio.sleep(3)
        return album.handle(request)

    state["handler"] = handle
    waits = []
    for gap in (237, 240):
        began = time.monotonic()
        client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})
        waits.append(time.monotonic() - began)
        later(mp4_cache, gap)

    assert waits[0] >= album_context.CONTEXT_SECONDS and waits[1] < album_context.CONTEXT_SECONDS, waits


def test_two_phones_on_the_two_files_of_one_song_each_stay_on_their_own(upstream, client, mp4_cache, tmp_path):
    """A song made without the song before (a read that failed once), then, once LOST_SECONDS have
    passed, made again with it, is two files. A phone streaming each, their pieces interleaved, must
    each be answered from its own file - the pins keep several files of the song as it is now, and a
    piece re-pins its file with its version. (The re-check's reproduction; it catches a pin kept
    without its version.)"""
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-1"))
    reads_fail(album, "song-1", 500, times=1)
    a = client.get(stream("song-2"))
    later(mp4_cache, player_cache.LOST_SECONDS + 1)
    b = client.get(stream("song-2"))
    assert a.headers["etag"] != b.headers["etag"]
    for i, (who, head) in enumerate(zip("ABABA", (a, b, a, b, a))):
        lo = 1000 * (i + 1)
        piece = client.get(stream("song-2"), headers={"Range": f"bytes={lo}-{lo + 999}", "If-Range": head.headers["etag"]})
        assert (piece.status_code, piece.headers["etag"], piece.content) == (206, head.headers["etag"],
                                                                             head.content[lo:lo + 1000]), who


def test_two_first_requests_on_the_url_way_are_one_file(upstream, mp4_cache):
    """
    Safari's probe and the readout's come together, and a hiccup meets only the second: made side by
    side, it got a plan without its album and finished last, so Safari's next range came from a file
    of another length than its probe said. Both wait on one plan now: one make, one file.
    """
    libraries()
    state, _ = upstream
    album = AlbumNavidrome({"one": hires((4096,) * 2 + (9,)), "two": hires((4096,) * 2 + (9,), seed=2),
                            "three": hires((4096,) * 2 + (9,), seed=3)})
    asked = {"getSong": 0}

    async def handle(request):
        if request.url.path.endswith("/getSong") and request.url.params.get("id") == "two":
            asked["getSong"] += 1
            if asked["getSong"] == 2:
                await asyncio.sleep(0.5)
                return httpx.Response(500, text="boom")
        await asyncio.sleep(0.01)
        return album.handle(request)

    state["handler"] = handle

    async def safari():
        element = asyncio.ensure_future(mp4_cache.answer("two", Probe("bytes=0-1"), 48000))
        while not album.calls:
            await asyncio.sleep(0.001)
        readout = asyncio.ensure_future(mp4_cache.answer("two", Probe("bytes=0-1"), 48000))
        first, second = await element, await readout
        await body_of(first), await body_of(second)
        rest = await mp4_cache.answer("two", Probe("bytes=2-"), 48000)
        await body_of(rest)
        return first, second, rest

    first, second, rest = asyncio.run(safari())
    total = lambda answer: answer.headers["content-range"].rsplit("/", 1)[1]  # noqa: E731

    assert first.headers["etag"] == second.headers["etag"] == rest.headers["etag"]
    assert total(first) == total(second) == total(rest)
    assert len([p for p in mp4_cache.directory.iterdir() if p.suffix == ".mp4"]) == 1, "one make, one file"


def test_chromium_starting_every_play_from_byte_0_is_a_new_play_long_after(upstream, client, mp4_cache, tmp_path):
    """
    Chromium asks for resampled songs the URL way too, and starts every play with `bytes=0-` - which
    reads as carrying on. So one make that failed kept the song on the FLAC for good (not resampled,
    3 dB louder), and a song whose audio was replaced was served from the old file hours later. Long
    after the URL was last answered it is a new play: the next play is resampled, its seek comes
    from the same file, and a replaced song is the new one.
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    url = stream("song-2", "mp4")
    real = album.handle
    dropped = {"left": 1}

    def handle(request):
        if request.url.path.endswith("/stream") and not request.headers.get("range") and dropped["left"]:
            dropped["left"] -= 1
            return httpx.Response(500, text="boom")
        return real(request)

    state["handler"] = handle
    assert client.get(url, headers={"Range": "bytes=0-"}).headers["content-type"] == "audio/flac"
    later(mp4_cache, 5)
    assert client.get(url, headers={"Range": "bytes=20000-"}).headers["content-type"] == "audio/flac"
    assert client.get(url, headers={"Range": "bytes=0-"}).headers["content-type"] == "audio/flac", \
        "the rest of that play: the FLAC it began as"

    later(mp4_cache, 3600)
    play = client.get(url, headers={"Range": "bytes=0-"})
    seek = client.get(url, headers={"Range": "bytes=20000-"})
    assert play.headers["content-type"] == seek.headers["content-type"] == "audio/mp4"
    assert play.headers["etag"] == seek.headers["etag"] and play.headers["x-deadwax-resampled"] == "192000-48000"

    album.files["song-2"] = write_flac(sf, tmp_path / "new.flac", music(np, 192000, 64002, seed=9), 192000).read_bytes()
    album.modified["song-2"] = LATER
    later(mp4_cache, 3600)
    assert client.get(url, headers={"Range": "bytes=0-"}).headers["etag"] != play.headers["etag"]


def test_safaris_rest_straight_after_its_probe_is_still_the_probes_file(upstream, client, mp4_cache, tmp_path):
    """Safari's `bytes=0-` straight after its probe is the same words as Chromium's new play, and is
    carried on from the probe's file - though the song beside it was retagged, and what Navidrome
    said about the album is no longer believed, so a new play would be another file."""
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})
    later(mp4_cache, player_cache.VERSION_SECONDS - 5)
    probe = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})
    album.modified["song-3"] = LATER
    later(mp4_cache, 6)
    rest = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-"})
    later(mp4_cache, player_cache.VERSION_SECONDS)
    new_play = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-"})

    assert rest.headers["etag"] == probe.headers["etag"]
    assert new_play.headers["etag"] != probe.headers["etag"]


# ---------------------------------------------------------------- leaving the stream

def handles_opened(monkeypatch) -> list:
    """Every cached file opened from here on - a fragmented MP4 made into an MP4, a file served -
    so a test can see that each was closed again."""
    opened, real = [], player_cache._open_cached

    def watched(path):
        handle = real(path)
        opened.append(handle)
        return handle

    monkeypatch.setattr(player_cache, "_open_cached", watched)
    return opened

def test_leaving_the_stream_gets_the_same_resampled_song_without_making_it_again(upstream, client, mp4_cache,
                                                                                 monkeypatch, tmp_path, caplog):
    """
    The page leaving the gapless stream in the middle of a resampled song - the AirPlay button, the
    switch turned off, a stream that failed - asks for that song's resampled MP4 the URL way. It is
    made from the stream's own fragmented MP4: no download, no resample, so the song carries on at
    once and at the level it had - the MP4 a make of it gives, byte for byte.
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    caplog.set_level(logging.INFO)
    in_stream = client.get(stream("song-2"))

    real = resample.resample_file

    def again(*args, **kwargs):
        raise AssertionError("resampled a second time")

    monkeypatch.setattr(player_cache.resample, "resample_file", again)
    opened = handles_opened(monkeypatch)
    probe = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})
    left = client.get(stream("song-2", "mp4"))

    assert (probe.status_code, probe.headers["content-type"], left.headers["content-type"]) == (206, "audio/mp4",
                                                                                              "audio/mp4")
    assert left.headers["x-deadwax-resampled"] == "192000-48000" and album.whole["song-2"] == 1
    assert flac_inside(left.content) == flac_inside(in_stream.content), "the very same frames"
    assert said(caplog, "out of the fragmented MP4 of it the gapless player has - no download, no resample")
    assert leftovers(mp4_cache) == []
    assert opened and all(handle.closed for handle in opened), "the stream's copy closed once it was made into the MP4"
    monkeypatch.setattr(player_cache.resample, "resample_file", real)
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / "made-the-ordinary-way"))
    assert client.get(stream("song-2", "mp4")).content == left.content, "the MP4 a make of it gives"


def test_leaving_a_stream_that_played_it_without_a_neighbour_costs_no_download_either(upstream, client, mp4_cache,
                                                                                      tmp_path):
    """The stream's copy was made without the song before it, which still can't be read: the MP4 is
    made from that copy, under the plan it really had - still no second download."""
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    reads_fail(album, "song-1", 500)
    in_stream = client.get(stream("song-2"))
    left = client.get(stream("song-2", "mp4"))
    assert left.headers["content-type"] == "audio/mp4" and album.whole["song-2"] == 1
    assert flac_inside(left.content) == flac_inside(in_stream.content)


def boxes_of(data: bytes) -> list[tuple[int, int, bytes]]:
    """A fragmented MP4's top-level boxes, as (where, size, kind)."""
    boxes, pos = [], 0
    while pos < len(data):
        size = int.from_bytes(data[pos:pos + 4], "big")
        boxes.append((pos, size, data[pos + 4:pos + 8]))
        pos += size
    return boxes


def mid_box(data: bytes) -> bytes:
    """Cut 1000 bytes into its last box, from the end: laid out as deadwax never lays them out."""
    return data[:-1000]


def without_its_last_fragment(data: bytes) -> bytes:
    """Whole to a box boundary, its last moof and mdat gone: its frames short of STREAMINFO's samples."""
    moofs = [where for where, _, kind in boxes_of(data) if kind == b"moof"]
    assert len(moofs) >= 2
    return data[:moofs[-1]]


@pytest.mark.parametrize("damage", [mid_box, without_its_last_fragment], ids=["cut mid-box", "its last fragment gone"])
def test_a_stream_copy_that_isnt_whole_is_cleared_out_and_the_mp4_made_the_ordinary_way(upstream, client, mp4_cache,
                                                                                        monkeypatch, tmp_path, caplog,
                                                                                        damage):
    """
    The stream's copy of a resampled song cut short - a power cut on a filesystem that doesn't order
    the rename after the data, a disk error. Cut mid-box, making the MP4 out of it failed with a
    traceback, and the URL way got the 192 kHz FLAC, 3 dB louder, at every fresh start while the copy
    was there; cut at a box boundary, its FLAC was short of STREAMINFO's samples and the resampled MP4
    was refused for good, even once the copy had gone. The copy is cleared out now, and the song is
    downloaded and resampled in the same make: the MP4 an ordinary make gives, byte for byte.
    """
    np, sf, _ = libraries()
    lengths = (96001, 192000 * 3 + 2, 96000)
    files = cut(np, sf, tmp_path, music(np, 192000, sum(lengths), level=0.5), lengths)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-2"))
    [copy] = fragmented(mp4_cache)
    copy.write_bytes(damage(copy.read_bytes()))
    caplog.set_level(logging.INFO)
    opened = handles_opened(monkeypatch)

    probe = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})
    whole = client.get(stream("song-2", "mp4"))
    later(mp4_cache, 3600)
    again = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})

    for answer in (probe, whole, again):
        assert answer.headers["content-type"] == "audio/mp4"
        assert answer.headers["x-deadwax-resampled"] == "192000-48000"
    assert not copy.exists(), "the copy that isn't whole cleared out"
    assert album.whole["song-2"] == 2, "the stream's download, and the one make's"
    assert mp4_cache._refused == {}
    assert said(caplog, "in the cache isn't whole") and not [r for r in caplog.records if r.exc_info]
    assert leftovers(mp4_cache) == []
    assert opened and all(handle.closed for handle in opened), "the copy that isn't whole closed too"
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / "made-the-ordinary-way"))
    assert client.get(stream("song-2", "mp4")).content == whole.content


def test_each_containers_format_version_is_in_its_resampled_files_key(upstream, mp4_cache, monkeypatch):
    """A resampled song's key carries its container's own format version, as the song's as it is
    does: a new muxer behind one container is a new name for that container's resampled files, so
    one made by the old muxer is never served under the new one's - and the other's stay valid."""
    state, _ = upstream
    serving(state, {"song": hires((4096,) * 6 + (9,))})
    version, plan = plan_of(mp4_cache, "song")

    def keys():
        return [version.key_for(wrap, plan) for wrap in (player_cache.MP4_WRAP, player_cache.FMP4_WRAP)]

    mp4, fmp4 = keys()
    fmp4_version = player_cache.FMP4_FORMAT_VERSION
    monkeypatch.setattr(player_cache, "FMP4_FORMAT_VERSION", fmp4_version + 1)
    bumped = keys()
    assert bumped[0] == mp4 and bumped[1] != fmp4, "a new fragmented MP4 muxer renames its files alone"
    monkeypatch.setattr(player_cache, "FMP4_FORMAT_VERSION", fmp4_version)
    monkeypatch.setattr(player_cache, "FORMAT_VERSION", player_cache.FORMAT_VERSION + 1)
    bumped = keys()
    assert bumped[0] != mp4 and bumped[1] == fmp4, "a new MP4 muxer renames its files alone"


# ---------------------------------------------------------------- stopping

def test_a_phone_that_hangs_up_during_the_resample_stops_it_within_a_block(upstream, mp4_cache, monkeypatch, caplog):
    """
    Through start()'s app, the way uvicorn serves it: the phone leaves while the song is being
    resampled, the route notices, and the resample - asked to stop - ends within a block instead of
    running to the end with the gate held. Nothing is left behind, and the gate is free.
    """
    libraries()
    state, _ = upstream
    #? a long song of silence: a few dozen bytes a frame on disk, the whole of it to resample
    song = constant_flac(bps=24, blocks=(4096,) * 3000)
    serving(state, {"song": song})
    monkeypatch.setattr(download_routes, "DISCONNECT_CHECK_SECONDS", 0.01)
    monkeypatch.setattr(resample, "BLOCK_FRAMES", 8192)
    real = resample.resample_file
    seen: dict = {}

    def watched(*args, **kwargs):
        seen["began"] = time.monotonic()
        try:
            return real(*args, **kwargs)
        except BaseException as e:
            seen["raised"] = type(e).__name__
            raise
        finally:
            seen["ended"] = time.monotonic()

    monkeypatch.setattr(player_cache.resample, "resample_file", watched)
    caplog.set_level(logging.INFO)
    app = start()
    sent = []

    async def hang_up_while_resampling():
        first = True

        async def receive():
            nonlocal first
            if first:
                first = False
                return {"type": "http.request", "body": b"", "more_body": False}
            while "began" not in seen:
                await asyncio.sleep(0.005)
            return {"type": "http.disconnect"}

        async def send(message):
            sent.append(message)

        path = "/deadwax/navidrome/stream/song"
        scope = {"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1", "method": "GET",
                 "scheme": "http", "path": path, "root_path": "", "raw_path": path.encode(),
                 "query_string": b"format=raw&wrap=fmp4&max_rate=48000",
                 "headers": [(b"host", b"test"), (b"range", HEAD.encode())], "server": ("test", 80),
                 "client": ("phone", 1)}
        await app(scope, receive, send)
        await asyncio.sleep(0.1)

    asyncio.run(hang_up_while_resampling())

    stopped_in = seen["ended"] - seen["began"]
    path = mp4_cache.directory / "whole.flac"
    began = time.monotonic()
    version = asyncio.run(mp4_cache._version("song"))
    plan = asyncio.run(mp4_cache.albums.plan(version, 48000))
    part = mp4_cache.directory / "source.flac"
    part.write_bytes(song)
    real(part, path, plan=plan)
    whole = time.monotonic() - began
    part.unlink()
    path.unlink()

    assert seen["raised"] == "Stopped"
    assert stopped_in < whole / 2, f"stopped after {stopped_in:.2f} s of a {whole:.2f} s resample"
    assert [m["status"] for m in sent if m["type"] == "http.response.start"] == [204]
    assert said(caplog, "was stopped - nobody was waiting for it")
    assert leftovers(mp4_cache) == [] and fragmented(mp4_cache) == []
    assert mp4_cache._working == {} and not mp4_cache._gate_lock.locked()
    assert not mp4_cache._resample_lock.locked()


def test_another_songs_repackage_never_waits_for_a_resample(upstream, mp4_cache, monkeypatch):
    """
    A long hi-res song resampling for one phone - a minute of work on a NAS - and a CD song asked for
    by another meanwhile: the CD song's repackage, 50 ms of work, is answered at once, not after the
    resample. Resamples keep a gate of their own; the repackages' is for holding a song in memory,
    which a resample doesn't.
    """
    libraries()
    state, _ = upstream
    serving(state, {"hi": constant_flac(bps=24), "cd": FLAC})
    real = resample.resample_file
    begun, finish = threading.Event(), threading.Event()

    def held(*args, **kwargs):
        #? a resample that goes on until the test says - however long a NAS takes
        begun.set()
        finish.wait(10)
        return real(*args, **kwargs)

    monkeypatch.setattr(player_cache.resample, "resample_file", held)
    app = start()

    async def both():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as phones:
            hi = asyncio.create_task(phones.get(stream("hi"), headers={"Range": HEAD}))
            while not begun.is_set():
                await asyncio.sleep(0.005)
            try:
                cd = await asyncio.wait_for(phones.get(stream("cd", capped=False), headers={"Range": HEAD}), 5)
                still_resampling = not hi.done()
            finally:
                finish.set()
            return cd, still_resampling, await hi

    cd, still_resampling, hi = asyncio.run(both())

    assert cd.status_code == 206 and "x-deadwax-resampled" not in cd.headers
    assert still_resampling, "the CD song was answered while the resample was still running"
    assert hi.status_code == 206 and hi.headers["x-deadwax-resampled"] == "192000-48000"


def test_a_song_too_short_to_reach_the_albums_grid_is_sent_as_it_is(upstream, client, mp4_cache, tmp_path):
    """A song two samples long whose album's grid next falls three samples in has nothing to resample
    to: the stream is told so in a 415 and plays it the ordinary way, the URL way gets the FLAC as it
    is, and no empty file is made or kept."""
    np, sf, _ = libraries()
    samples = music(np, 192000, 96003, level=0.5)
    files = cut(np, sf, tmp_path, samples, (96001, 2))
    state, _ = upstream
    serving(state, files)

    refused = client.get(stream("song-2"), headers={"Range": HEAD})
    flac = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})

    assert refused.status_code == 415
    assert "it is 2 sample(s) long, and none of them falls on the album's 48 kHz grid" in refused.json()["detail"]
    assert (flac.headers["content-type"], flac.content) == ("audio/flac", files["song-2"][:2])
    assert fragmented(mp4_cache) == [] and leftovers(mp4_cache) == []


def test_a_song_damaged_part_way_through_is_downloaded_once_and_refused(upstream, client, mp4_cache, tmp_path,
                                                                       caplog):
    """One bit flipped in the middle of a hi-res song: libFLAC can't decode that frame, every time.
    It is refused and remembered - the stream told so in a 415, the URL way given the FLAC - not
    downloaded whole and resampled up to that frame again for every request, with a traceback each."""
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    data = bytearray(files["song-2"])
    data[len(data) // 2] ^= 0x01
    files["song-2"] = bytes(data)
    state, _ = upstream
    album = serving(state, files)

    refused = [client.get(stream("song-2"), headers={"Range": HEAD}) for _ in range(3)]
    flac = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})
    later(mp4_cache)
    again = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})

    for answer in refused:
        assert answer.status_code == 415 and "couldn't decode all of it" in answer.json()["detail"]
    assert flac.headers["content-type"] == again.headers["content-type"] == "audio/flac"
    assert album.whole["song-2"] == 2, "once for each container, and never again"
    assert not [r for r in caplog.records if r.exc_info], "no traceback"
    assert leftovers(mp4_cache) == [] and fragmented(mp4_cache) == []


def sizes_of(client, monkeypatch, tmp_path, songs) -> dict[str, int]:
    """What each song's resampled fragmented MP4 comes to, made in a roomy cache of its own."""
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / "measured"))
    return {song: int(client.get(stream(song), headers={"Range": HEAD}).headers["content-range"].rsplit("/", 1)[1])
            for song in songs}


def long_album(np, sf, tmp_path, lengths=(192000, 384000, 192000, 192000)) -> dict[str, bytes]:
    return cut(np, sf, tmp_path, music(np, 192000, sum(lengths), level=0.5), lengths)


def test_a_resampled_song_takes_the_cap_at_the_size_it_resamples_to(upstream, client, monkeypatch, tmp_path):
    """
    The cap bounds the files made, and a resampled one is a quarter of its source or less. Judged at
    the source's size, the song after one being played - whose source didn't fit beside it, though
    its resampled file easily did - was a 503 to the stream until the join, and the FLAC as it is to
    the URL way.
    """
    np, sf, _ = libraries()
    files = long_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    sizes = sizes_of(client, monkeypatch, tmp_path, ["song-1", "song-2"])
    cap = sizes["song-1"] + sizes["song-2"] * 3 // 2
    assert sizes["song-1"] + len(files["song-2"]) > cap, "the source wouldn't fit beside the song playing"

    for wrap in ("fmp4", "mp4"):
        monkeypatch.setattr(player_cache, "cache", Mp4Cache(tmp_path / f"capped-{wrap}", max_bytes=cap))
        playing = client.get(stream("song-1", wrap), headers={"Range": HEAD})
        after = client.get(stream("song-2", wrap), headers={"Range": HEAD})
        assert playing.status_code == after.status_code == 206, after.text
        assert after.headers["content-type"] == "audio/mp4" and after.headers["x-deadwax-resampled"] == "192000-48000"


def test_a_resampled_song_clears_only_the_room_its_file_needs(upstream, client, monkeypatch, tmp_path):
    """Nothing being played: room for three older songs and the new one's resampled file. Judged at
    its source's size it cleared every one of them, for a file a quarter that size."""
    np, sf, _ = libraries()
    files = long_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    sizes = sizes_of(client, monkeypatch, tmp_path, list(files))
    older = ["song-1", "song-3", "song-4"]
    #? room for the three and the new one's file, as made or as _kept_size() expects it, whichever is more
    cap = sum(sizes[song] for song in older) + max(sizes["song-2"], len(files["song-2"]) // 4) * 5 // 4
    capped = Mp4Cache(tmp_path / "capped", max_bytes=cap)
    monkeypatch.setattr(player_cache, "cache", capped)
    now = [time.time()]
    capped.wall_clock = lambda: now[0]
    for song in older:
        now[0] += player_cache.IN_USE_SECONDS + 1
        assert client.get(stream(song), headers={"Range": HEAD}).status_code == 206
    now[0] += player_cache.IN_USE_SECONDS + 1

    made = client.get(stream("song-2"), headers={"Range": HEAD})

    assert made.status_code == 206 and len(fragmented(capped)) == 4, "every older song kept"
    assert sum(path.stat().st_size for path in fragmented(capped)) <= cap


def test_a_resampled_make_needs_room_on_the_disk_for_its_download(upstream, client, mp4_cache, monkeypatch,
                                                                  tmp_path):
    """
    The cap is judged at what a resampled song comes out as, the disk at what the make writes: the
    whole download, then the resampled FLAC beside it - two copies of about the source, not of the
    file made. A disk with room for two of the file but not two of the source clears the song played
    longest ago to make it; and with nothing to clear, the song isn't made, and nothing is fetched.
    """
    np, sf, _ = libraries()
    files = long_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-1", capped=False), headers={"Range": HEAD})
    [older] = fragmented(mp4_cache)
    played_long_ago(mp4_cache)
    source = len(files["song-2"])
    #? two of its file fit as it is (a quarter of the source each); two of the source once `older` goes
    a_disk(monkeypatch, mp4_cache, player_cache.DISK_SPARE_BYTES + 2 * source + older.stat().st_size // 2)

    made = client.get(stream("song-2"), headers={"Range": HEAD})

    assert made.status_code == 206 and made.headers["x-deadwax-resampled"] == "192000-48000"
    assert not older.exists(), "cleared to make room for the download"

    empty = Mp4Cache(tmp_path / "empty")
    monkeypatch.setattr(player_cache, "cache", empty)
    a_disk(monkeypatch, empty, player_cache.DISK_SPARE_BYTES + 2 * len(files["song-3"]) - 1)
    short = client.get(stream("song-3"), headers={"Range": HEAD})
    assert short.status_code == 503 and fragmented(empty) == []
    assert album.whole["song-3"] == 0, "nothing fetched"


def test_a_16_bit_songs_file_is_reserved_at_what_it_comes_out_as(upstream, client, monkeypatch, tmp_path):
    """
    A 16-bit source resampled is written at 24 bits, and its file comes out bigger than the rate and
    the depth alone say - here about 1.23 times. So it is reserved a quarter more: with room in the
    cap for the song being played and the plain estimate, but not for the file, the new song is told
    to wait, since the song being played can't be cleared for it - rather than made, taking the cache
    past its cap by what it came out over.
    """
    np, sf, _ = libraries()
    lengths = (192000, 384000, 192000)
    samples = music(np, 192000, sum(lengths), level=0.5)
    files, at = {}, 0
    for i, n in enumerate(lengths):
        files[f"song-{i + 1}"] = write_flac(sf, tmp_path / f"16-{i}.flac", samples[at:at + n], 192000,
                                            bits=16).read_bytes()
        at += n
    state, _ = upstream
    serving(state, files)
    sizes = sizes_of(client, monkeypatch, tmp_path, ["song-1", "song-2"])
    version, plan = plan_of(player_cache.cache, "song-2")
    estimate = plan.estimated_bytes(version.size)
    assert plan.bits == 16 and sizes["song-2"] > estimate, "the case: it comes out over the plain estimate"
    assert Mp4Cache._kept_size(version, plan) >= sizes["song-2"], "reserved at no less than it comes out as"

    cap = sizes["song-1"] + (estimate + sizes["song-2"]) // 2
    capped = Mp4Cache(tmp_path / "capped", max_bytes=cap)
    monkeypatch.setattr(player_cache, "cache", capped)
    playing = client.get(stream("song-1"), headers={"Range": HEAD})
    after = client.get(stream("song-2"), headers={"Range": HEAD})

    assert playing.status_code == 206
    assert after.status_code == 503 and after.json()["scope"] == "song"
    assert sum(path.stat().st_size for path in fragmented(capped)) <= cap, "the cap holds"


def test_a_resampled_file_over_its_room_never_clears_the_song_being_played(upstream, client, tmp_path, monkeypatch):
    """
    A resampled song so short that its file is mostly the container's boxes comes out far over the
    room made for it: its estimate, a quarter of a tiny source. What it comes out over that is
    trimmed from songs played longest ago, never from one being played - measured against the source
    instead, a resampled file's overhang read as nothing, and the song on the playhead was cleared
    for it and made again at its next piece.
    """
    libraries()
    state, _ = upstream
    album = serving(state, {"playing": FLAC, "song": hires((4096,) * 6 + (9,))})
    cache = Mp4Cache(tmp_path / "c")
    version, plan = plan_of(cache, "song")
    kept = Mp4Cache._kept_size(version, plan)
    playing = flac_to_fmp4(FLAC)
    cache._max_bytes = len(playing) + kept
    monkeypatch.setattr(player_cache, "cache", cache)

    etag = client.get(stream("playing", capped=False), headers={"Range": HEAD}).headers["etag"]
    made = client.get(stream("song"), headers={"Range": HEAD})
    piece = client.get(stream("playing", capped=False), headers={"Range": "bytes=1000-1999", "If-Range": etag})

    assert made.status_code == 206 and len(made.content) > version.size > kept, \
        "the case: over its room, and over its source"
    assert (piece.status_code, piece.content) == (206, playing[1000:2000])
    assert album.whole["playing"] == 1, "the song being played kept, never made again"


def test_an_mp4_made_from_the_stream_copy_over_its_room_never_clears_the_song_being_played(upstream, client,
                                                                                          tmp_path, monkeypatch):
    """The same rule on the other way an MP4 of a resampled song is made - from its stream copy, when
    the page leaves the stream: what the file comes out over its room is trimmed from songs played
    longest ago, and measured against that room, not against the source."""
    libraries()
    state, _ = upstream
    album = serving(state, {"playing": FLAC, "song": hires((4096,) * 6 + (9,))})
    cache = Mp4Cache(tmp_path / "c")
    version, plan = plan_of(cache, "song")
    kept = Mp4Cache._kept_size(version, plan)
    playing = flac_to_fmp4(FLAC)
    monkeypatch.setattr(player_cache, "cache", cache)

    etag = client.get(stream("playing", capped=False), headers={"Range": HEAD}).headers["etag"]
    in_stream = client.get(stream("song"))
    cache._max_bytes = len(playing) + len(in_stream.content) + kept
    left = client.get(stream("song", "mp4"))
    piece = client.get(stream("playing", capped=False), headers={"Range": "bytes=1000-1999", "If-Range": etag})

    assert left.headers["content-type"] == "audio/mp4" and album.whole["song"] == 1, "made from the stream's copy"
    assert len(left.content) > version.size > kept, "the case: over its room, and over its source"
    assert (piece.status_code, piece.content) == (206, playing[1000:2000])
    assert album.whole["playing"] == 1, "the song being played kept, never made again"


def test_an_mp4_made_from_the_stream_copy_needs_disk_room_for_its_file_not_its_source(upstream, client,
                                                                                      mp4_cache, monkeypatch,
                                                                                      tmp_path):
    """Made from the stream's copy, an MP4 writes only the resampled FLAC and the MP4 - two of the
    file, about a quarter of the source each - and downloads nothing. A disk with room for those but
    not for two of the source still takes it, with the stream's copy (being played) kept."""
    np, sf, _ = libraries()
    files = long_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    in_stream = client.get(stream("song-2"))
    version, plan = plan_of(mp4_cache, "song-2")
    kept = Mp4Cache._kept_size(version, plan)
    assert 2 * version.size > 2 * kept + (1 << 20), "the case: two of the source are far more than two of the file"
    held = sum(path.stat().st_size for path in mp4_cache.directory.iterdir())
    a_disk(monkeypatch, mp4_cache, held + player_cache.DISK_SPARE_BYTES + 2 * kept + (1 << 20))

    left = client.get(stream("song-2", "mp4"))

    assert left.headers["content-type"] == "audio/mp4" and left.headers["x-deadwax-resampled"] == "192000-48000"
    assert album.whole["song-2"] == 1 and len(in_stream.content) > 0


def test_a_new_headroom_is_a_new_file(upstream, mp4_cache, monkeypatch):
    """The headroom is in a resampled song's key, so a deadwax lowering songs by another amount
    never serves one lowered the old way under the new way's name - with RESAMPLE_FORMAT_VERSION
    left as it is."""
    state, _ = upstream
    serving(state, {"song": hires((4096,) * 6 + (9,))})
    version, plan = plan_of(mp4_cache, "song")
    before = [version.key_for(wrap, plan) for wrap in (player_cache.MP4_WRAP, player_cache.FMP4_WRAP)]
    monkeypatch.setattr(resample, "HEADROOM_DB", 1.0)
    after = [version.key_for(wrap, plan) for wrap in (player_cache.MP4_WRAP, player_cache.FMP4_WRAP)]
    assert before[0] != after[0] and before[1] != after[1]
    assert version.key_for(player_cache.MP4_WRAP) == version.key, "the song as it is keeps its key"


# ---------------------------------------------------------------- a disk that fills while resampling

def test_a_disk_that_fills_during_the_resample_clears_older_songs_and_resamples_once_more(upstream, client,
                                                                                         mp4_cache, monkeypatch,
                                                                                         tmp_path, caplog):
    """
    Something else fills the disk while a song is being resampled. libsndfile would call that a
    "System error." and the make gave up; the disk's own ENOSPC now reaches the make, which clears
    the songs played longest ago and resamples once more - from the download it already has.
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-1", capped=False))
    [older] = fragmented(mp4_cache)
    played_long_ago(mp4_cache)
    real, opened = resample._open_output, []

    def fills_once(target):
        opened.append(target)
        return ADiskThatFills(target, 5000) if len(opened) == 1 else real(target)

    monkeypatch.setattr(resample, "_open_output", fills_once)
    caplog.set_level(logging.INFO)
    answer = client.get(stream("song-2"), headers={"Range": HEAD})

    assert answer.status_code == 206 and answer.headers["x-deadwax-resampled"] == "192000-48000"
    assert not older.exists(), "the song played longest ago made room"
    assert len(opened) == 2, "resampled once more"
    assert album.whole["song-2"] == 1, "from the download it already had"
    assert said(caplog, "filled up while song song-2 was being put in a fragmented MP4")
    assert fragmented(mp4_cache) != [] and leftovers(mp4_cache) == []


def test_a_disk_that_stays_full_during_the_resample_is_asked_again_later_and_leaves_nothing(upstream, client,
                                                                                           mp4_cache, monkeypatch,
                                                                                           tmp_path, caplog):
    """Full again the second time: the stream is told to ask again in a moment (a full disk is no
    reason never to resample the song), the URL way gets the FLAC, nothing is left behind - and once
    the disk has room, the song is resampled."""
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    real = resample._open_output
    monkeypatch.setattr(resample, "_open_output", lambda target: ADiskThatFills(target, 5000))

    full = client.get(stream("song-2"), headers={"Range": HEAD})
    flac = client.get(stream("song-2", "mp4"), headers={"Range": "bytes=0-1"})

    assert full.status_code == 503 and full.json()["scope"] == "song"
    assert (flac.headers["content-type"], flac.content) == ("audio/flac", files["song-2"][:2])
    assert said(caplog, "No space left on device")
    assert fragmented(mp4_cache) == [] and leftovers(mp4_cache) == []

    monkeypatch.setattr(resample, "_open_output", real)
    again = client.get(stream("song-2"), headers={"Range": HEAD})
    assert again.status_code == 206 and again.headers["x-deadwax-resampled"] == "192000-48000"


def test_a_disk_that_fills_while_a_resampled_song_is_repackaged_repackages_it_once_more_without_resampling(
        upstream, client, mp4_cache, monkeypatch, tmp_path, caplog):
    """
    The resample done, something else fills the disk while its FLAC is repackaged. The download has
    gone by then, so resampling once more would have nothing to read and the song would be refused
    for good; the resampled FLAC is kept until the make ends, and only the repackage is tried again.
    """
    np, sf, _ = libraries()
    _, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    client.get(stream("song-1", capped=False))
    [older] = fragmented(mp4_cache)
    played_long_ago(mp4_cache)
    real_repackage, real_resample = player_cache._repackage, resample.resample_file
    calls = {"repackage": 0, "resample": 0}

    def fills_once(source, target, pieces):
        calls["repackage"] += 1
        if calls["repackage"] == 1:
            raise OSError(errno.ENOSPC, "No space left on device")
        return real_repackage(source, target, pieces)

    def counted(*args, **kwargs):
        calls["resample"] += 1
        return real_resample(*args, **kwargs)

    monkeypatch.setattr(player_cache, "_repackage", fills_once)
    monkeypatch.setattr(player_cache.resample, "resample_file", counted)
    caplog.set_level(logging.INFO)
    answer = client.get(stream("song-2"), headers={"Range": HEAD})

    assert answer.status_code == 206 and answer.headers["x-deadwax-resampled"] == "192000-48000"
    assert calls == {"repackage": 2, "resample": 1}, "the repackage alone was tried once more"
    assert album.whole["song-2"] == 1, "from the download it already had"
    assert not older.exists(), "the song played longest ago made room"
    assert said(caplog, "filled up while song song-2 was being put in a fragmented MP4")
    assert fragmented(mp4_cache) != [] and leftovers(mp4_cache) == []


# ---------------------------------------------------------------- the joins, end to end

def fetched_in_order(client, sf, songs) -> tuple[list, list[str]]:
    outs, headers = [], []
    for song in songs:
        answer = client.get(stream(song))
        assert answer.status_code == 200, answer.text
        samples, rate = decoded(sf, answer.content)
        assert rate == 48000
        outs.append(samples)
        headers.append(answer.headers["x-deadwax-resampled"])
    return outs, headers


def test_an_album_fetched_song_by_song_joins_into_one_resample_of_the_whole(upstream, client, tmp_path):
    """
    The promise, end to end. A 192 kHz album of three songs split at non-multiples of 4, each fetched
    from the route as the gapless player fetches it, decoded and laid end to end, is one resample of
    the whole album - the same length, every sample within the one LSB of 24-bit rounding - with each
    song exactly its count on the album's grid, so the page places them where they belong.
    """
    np, sf, soxr = libraries()
    samples, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)

    outs, headers = fetched_in_order(client, sf, files)
    joined = np.concatenate(outs)
    reference = continuous(np, soxr, samples, 192000, 48000)

    assert headers == ["192000-48000"] * 3
    phases = [resample.album_phase(sum(LENGTHS[:i]), 4) for i in range(3)]
    assert [len(out) for out in outs] == [resample.output_count(n, p, 4) for n, p in zip(LENGTHS, phases)]
    assert len(joined) == len(reference)
    assert np.abs(joined - reference).max() <= 1
    assert sum(album.whole.values()) == 3, "each song downloaded once; its neighbours only by range"


def test_the_same_album_without_its_context_clicks_at_the_joins(upstream, client, tmp_path):
    """What the context fixes: with Navidrome saying nothing about the album, each song is resampled
    alone, against silence - and off by thousands of LSB where it meets the next."""
    np, sf, soxr = libraries()
    samples, files = an_album(np, sf, tmp_path)
    state, _ = upstream
    album = serving(state, files)
    album.failing.add("getAlbum")

    outs, _ = fetched_in_order(client, sf, files)
    reference = continuous(np, soxr, samples, 192000, 48000)
    first = outs[0]
    end = len(first)

    assert np.abs(first[end - 100:] - reference[end - 100:end]).max() > 10000, "the end of the first song"
    assert np.abs(first[1000:end - 1000] - reference[1000:end - 1000]).max() <= 1, "away from the join, the same"


def over_in_the_middle(np, sf, tmp_path: Path, beyond: bool):
    """An album whose middle song goes over once resampled - a square wave just under full scale,
    within the headroom, or a song built to go past it (overshoot()) - between two songs of music,
    one piece cut in three."""
    lengths = (48001, 48002, 48000)
    middle = (overshoot(np, 192000, lengths[1] / 192000) if beyond
              else square(np, 192000, lengths[1] / 192000, 0.999, 1000))
    samples = np.concatenate([music(np, 192000, lengths[0], level=0.5), middle,
                              music(np, 192000, lengths[2], level=0.5, seed=2)])
    return samples, lengths, cut(np, sf, tmp_path, samples, lengths)


def test_a_song_that_goes_over_within_the_headroom_joins_its_neighbours_exactly(upstream, client, tmp_path, caplog):
    """
    The hard-clipped master's case, end to end: a song that goes past full scale once resampled,
    by less than the headroom, is lowered 3 dB like the songs beside it and no further - so the
    album joins into one resample of the whole scaled by the headroom's gain, each join exact within
    an LSB, with nothing clipped and nothing said beyond the usual.
    """
    np, sf, soxr = libraries()
    caplog.set_level(logging.INFO)
    samples, lengths, files = over_in_the_middle(np, sf, tmp_path, beyond=False)
    state, _ = upstream
    serving(state, files)

    outs, _ = fetched_in_order(client, sf, files)
    joined = np.concatenate(outs)
    exact = floats(np, soxr, samples, 192000, 48000)
    a, b = len(outs[0]), len(outs[0]) + len(outs[1])

    assert np.abs(exact[a:b]).max() > 1.1, "the middle song goes over once resampled, by over 1 dB"
    assert np.abs(exact).max() * GAIN < 1, "and fits in the headroom"
    assert np.abs(joined - np.rint(exact * FULL * GAIN)).max() <= 1
    assert len(said(caplog, "3 dB down, and put in")) == 3
    assert not said(caplog, "lowered a further")


def test_a_song_over_by_more_than_the_headroom_steps_at_its_joins_by_exactly_the_difference(upstream, client,
                                                                                           tmp_path, caplog):
    """
    A song that would clip even 3 dB down - a master clipped very hard - is lowered further by
    exactly enough, and said to be. The songs beside it aren't, so the joins on either side of it
    step in level by the difference and nothing more: the lowered song is one resample of the album
    times its own gain, the songs beside it one resample of the album times the headroom's - each
    within an LSB.
    """
    np, sf, soxr = libraries()
    caplog.set_level(logging.INFO)
    samples, lengths, files = over_in_the_middle(np, sf, tmp_path, beyond=True)
    state, _ = upstream
    serving(state, files)

    outs, _ = fetched_in_order(client, sf, files)
    exact = floats(np, soxr, samples, 192000, 48000)
    a, b = len(outs[0]), len(outs[0]) + len(outs[1])
    middle = exact[a:b]
    gain = min(TOP / (middle.max() * FULL), BOTTOM / (middle.min() * FULL))

    assert gain < GAIN, "past full scale even 3 dB down"
    assert np.abs(outs[0] - np.rint(exact[:a] * FULL * GAIN)).max() <= 1
    assert np.abs(outs[1] - np.rint(middle * FULL * gain)).max() <= 1
    assert np.abs(outs[2] - np.rint(exact[b:] * FULL * GAIN)).max() <= 1
    assert outs[1].max() == TOP or outs[1].min() == BOTTOM, "lowered no further than it had to be"
    [line] = said(caplog, "was lowered a further")
    further = float(re.search(r"lowered a further ([0-9.]+) dB so nothing clips", line).group(1))
    assert abs(further - (-20 * np.log10(gain) - resample.HEADROOM_DB)) < 0.006, "the log says the step it is"
    assert "song-2 was lowered" in line and "its joins with the songs beside it step in level by that much" in line
    assert [r.levelname for r in caplog.records if "lowered a further" in r.getMessage()] == ["WARNING"]


def test_the_album_fake_serves_only_what_it_holds():
    """The fake album this file leans on answers an album it doesn't hold as Navidrome does."""
    album = AlbumNavidrome({"song": FLAC})
    answer = album.handle(httpx.Request("GET", "http://navidrome:4533/rest/getAlbum?id=elsewhere"))
    assert answer.json()["subsonic-response"]["error"]["code"] == 70
