"""
The player's Normalization through the real app (2.0.0-player.62): the stream's and the scrub's `level`,
the copy deadwax makes at a level (src/resample.py), the gain it is made at (src/levels.py, measured by
src/loudness.py), where measurements are kept, and Info's and the album page's two routes.

And above all the promise the setting rests on - OFF IS TODAY'S PATH: every request without `level` is
answered with exactly the bytes and the ETag deadwax answered before levels existed (the ETags pinned by
the formulas they had at 2.0.0-player.61), with nothing measured and nothing kept. Then, levelled: the copy
is the source times the gain, rounded to 24 bits and nothing else; an album's songs fetched one at a time
join into the whole album levelled, sample for sample; levelled and resampled is quantised once; a copy is
never served for another gain.

Navidrome is test_album_context.py's fake album behind test_navidrome.py's fake client, and deadwax is
start()'s app, middleware and all. A test that needs one event loop for its whole life - a measurement
that carries on after the request that started it, requests at once - drives the app through httpx's
ASGI transport in one asyncio.run. The audio tests need numpy, soundfile and soxr, and skip without them
(never in CI - see test_resample.py's last test).
"""

import asyncio
import hashlib
import json
import logging
import sqlite3
import sys
import time
from pathlib import Path

import httpx
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import levels, loudness, player_cache, poller, resample  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.navidrome_endpoint import NavidromeError  # noqa: E402
from src.flac_mp4 import flac_to_fmp4, flac_to_mp4  # noqa: E402
from src.player_cache import FMP4_FORMAT_VERSION, FORMAT_VERSION, Mp4Cache  # noqa: E402
from src.resample import ResamplePlan  # noqa: E402
from src.routes import navidrome as navidrome_routes  # noqa: E402
from src.store import JobStore  # noqa: E402
import test_navidrome as navidrome_tests  # noqa: E402
from test_album_context import later, serving  # noqa: E402
from test_navidrome import STAMP, ok  # noqa: E402
from test_resample import constant_flac, floats, music, write_flac  # noqa: E402
from test_resampled_stream import decoded, streaminfo_in  # noqa: E402

#? test_navidrome.py's fake Navidrome client, the real app, and a cache of the test's own
configured, upstream, client, mp4_cache = (navidrome_tests.configured, navidrome_tests.upstream,
                                           navidrome_tests.client, navidrome_tests.mp4_cache)

FULL = float(1 << 23)
TOP, BOTTOM = (1 << 23) - 1, -(1 << 23)

#? a CD album's songs cut from one piece of music at lengths that aren't multiples of 4 (or of anything)
CD_LENGTHS = (44100 * 2 + 1, 44100 * 2 - 3, 44100 * 2 + 2)
#? and a hi-res one's, as test_resampled_stream.py cuts it
HI_LENGTHS = (96001, 64002, 96000)


def libs():
    return pytest.importorskip("numpy"), pytest.importorskip("soundfile"), pytest.importorskip("soxr")


def url(song: str, wrap: str | None = "fmp4", level: str | None = "album", capped: bool = False) -> str:
    query = "format=raw" + (f"&wrap={wrap}" if wrap else "") + ("&max_rate=48000" if capped else "")
    return f"/deadwax/navidrome/stream/{song}?{query}" + (f"&level={level}" if level else "")


def cd_album(np, sf, tmp_path: Path, lengths=CD_LENGTHS, bits: int = 16, level: float = 0.5, seed: int = 1):
    """An album cut from one piece of music: the 24-bit samples, and the songs as FLACs of `bits`."""
    samples = music(np, 44100, sum(lengths), level=level, seed=seed)
    files, at = {}, 0
    for i, n in enumerate(lengths):
        files[f"song-{i + 1}"] = write_flac(sf, tmp_path / f"cd-{seed}-{i + 1}.flac", samples[at:at + n], 44100,
                                            bits).read_bytes()
        at += n
    return samples, files


def hi_album(np, sf, tmp_path: Path):
    samples = music(np, 192000, sum(HI_LENGTHS), level=0.5)
    files, at = {}, 0
    for i, n in enumerate(HI_LENGTHS):
        files[f"song-{i + 1}"] = write_flac(sf, tmp_path / f"hi-{i + 1}.flac", samples[at:at + n], 192000).read_bytes()
        at += n
    return samples, files


def gain_of(response) -> float:
    kind, gain = response.headers["x-deadwax-level"].split()
    return float(gain)


def levelled(np, source, gain_db: float):
    """What a levelled copy must hold: the source (floats, 1.0 = full scale) times the gain, rounded to 24
    bits and clipped - the spec's clip(rint(x * 10**(g/20) * 2**23)), nothing else."""
    return np.clip(np.rint(source * 10 ** (gain_db / 20) * FULL), BOTTOM, TOP).astype(np.int64)


def measured(monkeypatch, delay: float = 0.0) -> list:
    """Every file measure_file is asked to measure, as it is asked - and slower by `delay` s."""
    seen = []
    real = loudness.measure_file

    def spy(path, *args, **kwargs):
        seen.append(Path(path).name)
        if delay:
            time.sleep(delay)
        return real(path, *args, **kwargs)

    monkeypatch.setattr(levels.loudness, "measure_file", spy)
    return seen


def kept_rows(store: JobStore) -> list[str]:
    with sqlite3.connect(store.path) as connection:
        return [row[0] for row in connection.execute("SELECT audio_key FROM loudness ORDER BY audio_key")]


@pytest.fixture
def store(tmp_path, mp4_cache):
    """deadwax's database, with the cache's levels keeping their measurements in it."""
    kept = JobStore(str(tmp_path / "state" / "deadwax.db"))
    kept.init()
    mp4_cache.levels.store = kept
    return kept


def run(work):
    """`work(client)` against the app on ONE event loop - what a running deadwax is: a measurement started
    by one request carries on after it."""
    async def go():
        transport = httpx.ASGITransport(app=start())
        async with httpx.AsyncClient(transport=transport, base_url="http://deadwax.test") as each:
            return await work(each)
    return asyncio.run(go())


def said(caplog, words: str) -> list[str]:
    return [record.getMessage() for record in caplog.records if words in record.getMessage()]


# ---------------------------------------------------------------- Off is today's path

def old_key(*material) -> str:
    """An ETag as deadwax made it before levels: the first 32 hex of the SHA-256 of its key's material."""
    return '"' + hashlib.sha256(json.dumps(list(material)).encode("utf-8")).hexdigest()[:32] + '"'


@pytest.mark.parametrize("kind", ["cd", "mp3", "hi-res"])
def test_off_is_todays_path_bit_for_bit(upstream, client, mp4_cache, store, tmp_path, monkeypatch, kind):
    """
    Every request without `level` - relayed, wrap=mp4, wrap=fmp4, each with and without max_rate, and a
    turntable window - answered as deadwax answered before levels existed: the bytes of the song as it is
    and of its MP4s; the ETags as the formulas of 2.0.0-player.61 make them (Version.key, the fragmented key,
    the resampled key with the plan's material as it was); the window the source's own samples where it says
    it sits; no X-Deadwax-Level anywhere; and nothing measured and nothing kept. (The resampled bodies are
    pinned sample for sample by test_resampled_stream.py and test_resample.py, which run without a level.)
    """
    np, sf, _ = libs()
    if kind == "cd":
        _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    elif kind == "hi-res":
        files = {"song-1": write_flac(sf, tmp_path / "hi.flac", music(np, 192000, 96001, level=0.5), 192000).read_bytes()}
    else:
        files = {"song-1": b"\xff\xfb\x90\x00" + bytes(40000)}
    state, _ = upstream
    album = serving(state, files)
    if kind == "mp3":
        album.types["song-1"] = "audio/mpeg"
        album.entries["song-1"].update(suffix="mp3", contentType="audio/mpeg")
    seen = measured(monkeypatch)
    data = files["song-1"]
    stamp = json.dumps([STAMP, None])

    relayed = client.get(url("song-1", wrap=None, level=None))
    assert relayed.content == data and "x-deadwax-level" not in relayed.headers
    for capped in (False, True):
        mp4 = client.get(url("song-1", "mp4", None, capped))
        fmp4 = client.get(url("song-1", "fmp4", None, capped))
        for answer in (mp4, fmp4):
            assert "x-deadwax-level" not in answer.headers
        if kind == "mp3":
            assert mp4.content == data and fmp4.status_code == 415
            continue
        if kind == "hi-res" and capped:
            material = [resample.RESAMPLE_FORMAT_VERSION, 48000, 48000, 0, resample.CONTEXT_SAMPLES, resample.HEADROOM_DB,
                        None, None]
            assert mp4.headers["etag"] == old_key(resample.RESAMPLE_FORMAT_VERSION, FORMAT_VERSION, "mp4", "song-1",
                                                  len(data), stamp, *material)
            assert fmp4.headers["etag"] == old_key(resample.RESAMPLE_FORMAT_VERSION, FMP4_FORMAT_VERSION, "fmp4",
                                                   "song-1", len(data), stamp, *material)
            assert mp4.headers["x-deadwax-resampled"] == fmp4.headers["x-deadwax-resampled"] == "192000-48000"
            continue
        assert mp4.content == flac_to_mp4(data) and fmp4.content == flac_to_fmp4(data)
        assert mp4.headers["etag"] == old_key(FORMAT_VERSION, "song-1", len(data), stamp)
        assert fmp4.headers["etag"] == old_key(FMP4_FORMAT_VERSION, "fmp4", "song-1", len(data), stamp)
        assert "x-deadwax-resampled" not in mp4.headers and "x-deadwax-resampled" not in fmp4.headers
    window = client.get("/deadwax/navidrome/scrub/song-1?at=0.2&seconds=1")
    assert window.status_code == (415 if kind == "mp3" else 200) and "x-deadwax-level" not in window.headers
    if kind != "mp3":
        first, samples, rate = map(int, window.headers["x-deadwax-window"].split("/"))
        cut, _ = sf.read(io_of(window.content), dtype="int32", always_2d=True)
        own, own_rate = sf.read(io_of(data), dtype="int32", always_2d=True)
        assert rate == own_rate and len(cut) == samples
        assert np.array_equal(cut, own[first:first + samples]), "the window is the source's own samples"
    assert seen == [] and kept_rows(store) == []
    assert mp4_cache.levels._read == {} and mp4_cache.levels._gains == {}


def test_without_a_level_the_plan_is_the_resamples_as_it_was():
    """ResamplePlan's material without a level is the list it always was, so every resampled file kept
    from before keeps its key; with one, the level's three things are added after it."""
    plan = ResamplePlan(max_rate=48000, source_rate=192000, out_rate=48000, channels=2, bits=24, total_samples=5)
    assert plan.material() == [1, 48000, 48000, 0, 16384, 3.0, None, None]
    assert plan.level_header is None and plan.resampled
    level = ResamplePlan(max_rate=None, source_rate=44100, out_rate=44100, channels=2, bits=16, total_samples=5,
                         level="album", gain_db=-7.42)
    assert level.material() == [1, None, 44100, 0, 16384, 3.0, None, None, resample.LEVEL_FORMAT_VERSION, "album", "-7.42"]
    assert level.level_header == "album -7.42" and not level.resampled
    up = ResamplePlan(max_rate=None, source_rate=44100, out_rate=44100, channels=2, bits=16, total_samples=5,
                      level="track", gain_db=1.2)
    assert up.level_header == "track +1.20"


def test_the_same_song_at_two_gains_is_two_files():
    """The gain is in the key BY VALUE: a copy is never served for another gain."""
    version = player_cache.Version(song_id="s", size=100, stamp="x")
    base = dict(max_rate=None, source_rate=44100, out_rate=44100, channels=2, bits=16, total_samples=5, level="album")
    keys = {version.key_for(wrap, ResamplePlan(**base, gain_db=gain))
            for wrap in (player_cache.MP4_WRAP, player_cache.FMP4_WRAP) for gain in (-7.42, -7.43)}
    keys |= {version.key_for(player_cache.FMP4_WRAP, ResamplePlan(**{**base, "level": "track"}, gain_db=-7.42))}
    assert len(keys) == 5
    assert version.key_for(player_cache.MP4_WRAP) == version.key


# ---------------------------------------------------------------- the copy

@pytest.mark.parametrize("bits", [16, 24])
@pytest.mark.parametrize("gain", [-7.42, 1.2, 0.0])
def test_a_levelled_copy_is_the_source_times_the_gain_and_nothing_else(tmp_path, bits, gain):
    """Decoded, the copy is exactly clip(rint(x * 10**(g/20) * 2**23)) of the source - 24-bit, undithered;
    at 0.00 dB the source's own samples, shifted to 24 bits."""
    np, sf, _ = libs()
    samples = music(np, 44100, 44100 + 777, level=0.4)
    source = write_flac(sf, tmp_path / "song.flac", samples, 44100, bits)
    own, _ = sf.read(str(source), dtype="float64", always_2d=True)
    plan = ResamplePlan(max_rate=None, source_rate=44100, out_rate=44100, channels=2, bits=bits,
                        total_samples=len(own), level="track", gain_db=gain)
    made = resample.resample_file(source, tmp_path / "out.flac", plan=plan)
    out, rate = sf.read(str(tmp_path / "out.flac"), dtype="int32", always_2d=True)
    info = sf.info(str(tmp_path / "out.flac"))
    assert (rate, info.subtype) == (44100, "PCM_24")
    assert np.array_equal(out >> 8, levelled(np, own, gain))
    assert made.lowered_db == -gain and made.beyond_db is None
    if gain == 0.0:
        shift = 8 if bits == 16 else 0
        assert np.array_equal(out >> 8, (samples >> 8 if bits == 16 else samples).astype(np.int64) << shift)


def test_a_level_that_would_clip_is_made_again_lowered_by_exactly_enough(tmp_path):
    """The gain's peak limit makes an over impossible unless a measurement was wrong - and then it does
    what the resample does: a second pass, lowered by exactly enough."""
    np, sf, _ = libs()
    samples = music(np, 44100, 44100, level=0.8)
    source = write_flac(sf, tmp_path / "song.flac", samples, 44100)
    own, _ = sf.read(str(source), dtype="float64", always_2d=True)
    plan = ResamplePlan(max_rate=None, source_rate=44100, out_rate=44100, channels=2, bits=24,
                        total_samples=len(own), level="track", gain_db=9.0)
    made = resample.resample_file(source, tmp_path / "out.flac", plan=plan)
    out, _ = sf.read(str(tmp_path / "out.flac"), dtype="int32", always_2d=True)
    assert (out >> 8).max() <= TOP and (out >> 8).min() >= BOTTOM
    assert made.beyond_db is not None and made.beyond_db > 0
    assert max((out >> 8).max(), -(out >> 8).min()) >= TOP - 1


def test_an_album_levelled_joins_sample_for_sample(upstream, client, mp4_cache, store, tmp_path):
    """
    Three songs cut from one piece of music at awkward places, each fetched levelled at its album's gain
    as the gapless player fetches it - and as Safari does, in an MP4: one gain for all three, 24-bit, and
    their samples concatenated are the whole album levelled, sample for sample. A gain has no memory, so
    the joins are exactly the source's.
    """
    np, sf, _ = libs()
    samples, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    whole = (samples >> 8) / 32768.0

    for wrap in ("fmp4", "mp4"):
        answers = [client.get(url(song, wrap)) for song in files]
        gains = {gain_of(answer) for answer in answers}
        assert len(gains) == 1, "one gain for the album"
        for answer in answers:
            assert answer.headers["x-deadwax-level"].startswith("album ")
            assert "x-deadwax-resampled" not in answer.headers
            assert streaminfo_in(answer.content)[:3] == (44100, 24, 2)
        joined = np.concatenate([decoded(sf, answer.content)[0] for answer in answers])
        assert np.array_equal(joined, levelled(np, whole, gains.pop()))


def test_levelled_and_resampled_is_quantised_once(upstream, client, mp4_cache, store, tmp_path):
    """
    A 24/192 album under Up to 48 kHz, levelled by album: one header pair on every song - the resample and
    the level - and the songs joined are one resample of the whole album at the level's gain in place of
    the 3 dB headroom, rounded once, within the 24-bit rounding's one LSB (as the resample's own joins are).
    The album's gain keeps the resample's room: its songs are resampled.
    """
    np, sf, soxr = libs()
    samples, files = hi_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    answers = [client.get(url(song, "fmp4", "album", capped=True)) for song in files]
    gain = gain_of(answers[0])
    for answer in answers:
        assert answer.headers["x-deadwax-resampled"] == "192000-48000"
        assert gain_of(answer) == gain
    joined = np.concatenate([decoded(sf, answer.content)[0] for answer in answers])
    wanted = np.rint(floats(np, soxr, samples, 192000, 48000) * FULL * 10 ** (gain / 20))
    assert len(joined) == len(wanted) and np.abs(joined - wanted).max() <= 1
    pooled = list((mp4_cache.levels._read).values())
    assert len(pooled) == 3
    expected = loudness.gain_for(loudness.loudness_of(pooled), max(m.peak for m in pooled), resample.HEADROOM_DB)
    assert gain == expected.gain_db


def test_one_resampled_song_reserves_the_room_for_its_whole_album(upstream, client, mp4_cache, store, tmp_path):
    """
    An album of CD songs and one 24/96, held by its peak: its one gain keeps the resample's 3 dB of room for
    EVERY song, each asked as the page asks it - the CD songs without the cap (the page sends it only with a song
    it resamples: ui/test/loudness.sim.cjs pins the addresses), the 24/96 with it under Up to 48 kHz and without
    under Original. The reserve is the album's, so it has one gain under either setting, and Info's route says
    that gain. An album of CD songs alone keeps none.
    """
    np, sf, _ = libs()
    #? quiet music with one loud click in it: brought up, and held by that peak
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2, 44100 * 2), level=0.1)
    clicked = music(np, 96000, 96000 * 2, level=0.1)
    clicked[5000] = int(0.9 * FULL)
    files["song-3"] = write_flac(sf, tmp_path / "96.flac", clicked, 96000).read_bytes()
    state, _ = upstream
    serving(state, files)
    cd = client.get(url("song-1", "fmp4", "album"))
    hi_capped = client.get(url("song-3", "fmp4", "album", capped=True))
    hi_original = client.get(url("song-3", "fmp4", "album"))
    pooled = list(mp4_cache.levels._read.values())
    peak = max(m.peak for m in pooled)
    lufs = loudness.loudness_of(pooled)
    held = loudness.gain_for(lufs, peak, resample.HEADROOM_DB).gain_db
    assert held < loudness.gain_for(lufs, peak, 0.0).gain_db, "held by the peak, with the room reserved"
    assert gain_of(cd) == gain_of(hi_capped) == gain_of(hi_original) == held, "one gain for the album"
    assert "x-deadwax-resampled" not in cd.headers and hi_capped.headers["x-deadwax-resampled"] == "96000-48000"
    for song, cap in (("song-1", ""), ("song-2", ""), ("song-3", "&max_rate=48000"), ("song-3", "")):
        mp4_cache.levels._gains.clear()
        assert client.get(f"/deadwax/navidrome/level/{song}?level=album{cap}").json()["gain_db"] == held, (song, cap)


def test_an_album_of_cd_songs_alone_keeps_no_room(upstream, client, mp4_cache, store, tmp_path):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2, 44100 * 2), level=0.1)
    state, _ = upstream
    clicked = music(np, 44100, 44100 * 2, level=0.1)
    clicked[5000] = int(0.9 * FULL)
    files["song-1"] = write_flac(sf, tmp_path / "click.flac", clicked, 44100, 16).read_bytes()
    serving(state, files)
    answer = client.get(url("song-2", "fmp4", "album"))
    pooled = list(mp4_cache.levels._read.values())
    peak = max(m.peak for m in pooled)
    lufs = loudness.loudness_of(pooled)
    assert gain_of(answer) == loudness.gain_for(lufs, peak, 0.0).gain_db
    assert gain_of(answer) > loudness.gain_for(lufs, peak, resample.HEADROOM_DB).gain_db, "held by its peak"


def test_a_hi_res_song_by_song_under_the_cap_keeps_the_resamples_room(upstream, client, mp4_cache, store, tmp_path):
    """By song, a 24/96 song held by its peak keeps the resample's 3 dB of room under Up to 48 kHz and none
    under Original (its copy isn't resampled) - and Info's route says the very gain each copy was made at."""
    np, sf, _ = libs()
    clicked = music(np, 96000, 96000 * 2, level=0.1)
    clicked[5000] = int(0.9 * FULL)
    state, _ = upstream
    serving(state, {"song-1": write_flac(sf, tmp_path / "96.flac", clicked, 96000).read_bytes()})
    capped = client.get(url("song-1", "fmp4", "track", capped=True))
    original = client.get(url("song-1", "fmp4", "track"))
    (measurement,) = mp4_cache.levels._read.values()
    assert gain_of(capped) == loudness.gain_for(measurement.loudness, measurement.peak, resample.HEADROOM_DB).gain_db
    assert gain_of(original) == loudness.gain_for(measurement.loudness, measurement.peak, 0.0).gain_db
    assert gain_of(capped) < gain_of(original)
    for level in ("track", "album"):
        mp4_cache.levels._gains.clear()
        info = client.get(f"/deadwax/navidrome/level/song-1?level={level}&max_rate=48000").json()
        assert info["gain_db"] == gain_of(capped), level
    mp4_cache.levels._gains.clear()
    assert client.get("/deadwax/navidrome/level/song-1?level=track").json()["gain_db"] == gain_of(original)
    #? by album the room is the album's, whatever the cap (test_one_resampled_song_reserves_the_room_for_its_whole_album)
    assert client.get("/deadwax/navidrome/level/song-1?level=album").json()["gain_db"] == gain_of(capped)


def test_by_song_each_song_has_its_own_gain(upstream, client, mp4_cache, store, tmp_path):
    np, sf, _ = libs()
    _, quiet = cd_album(np, sf, tmp_path, lengths=(44100 * 2,), level=0.1, seed=2)
    _, loud = cd_album(np, sf, tmp_path, lengths=(44100 * 2,), level=0.7, seed=3)
    state, _ = upstream
    serving(state, {"quiet": quiet["song-1"], "loud": loud["song-1"]})
    q = client.get(url("quiet", level="track"))
    lo = client.get(url("loud", level="track"))
    assert q.headers["x-deadwax-level"].startswith("track ") and gain_of(q) > gain_of(lo)
    album = client.get(url("quiet", level="album"))
    assert gain_of(album) != gain_of(q) and q.headers["etag"] != album.headers["etag"]


# ---------------------------------------------------------------- the key, and one URL one file

def test_an_album_that_gained_a_song_is_a_new_copy_and_a_carry_on_stays_on_its_file(upstream, client, mp4_cache,
                                                                                   store, tmp_path):
    """
    A song added to the album changes its pooled loudness, so its gain - and once what Navidrome said is
    looked at again, every levelled copy of it is a new file with a new ETag. A phone carrying on from the
    old copy stays on it: the gapless stream by If-Range (its pin), Safari's element by what its URL was
    last served (no If-Range from Safari).
    """
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2, 44100 * 2), level=0.2)
    state, _ = upstream
    album = serving(state, files)
    first = client.get(url("song-1", "fmp4"))
    safari = client.get(url("song-1", "mp4"))
    _, loud = cd_album(np, sf, tmp_path, lengths=(44100 * 2,), level=0.9, seed=4)
    album.files["song-3"] = loud["song-1"]
    album.modified["song-3"] = STAMP
    album.types["song-3"] = "audio/flac"
    album.entries["song-3"] = album.entry(2, "song-3", loud["song-1"])
    album.listed.append("song-3")
    later(mp4_cache)

    carried = client.get(url("song-1", "fmp4"), headers={"Range": "bytes=100-199", "If-Range": first.headers["etag"]})
    assert (carried.status_code, carried.content) == (206, first.content[100:200])
    on = client.get(url("song-1", "mp4"), headers={"Range": "bytes=100-199"})
    assert (on.status_code, on.content) == (206, safari.content[100:200])
    assert on.headers["etag"] == safari.headers["etag"]

    fresh = client.get(url("song-1", "fmp4"))
    assert gain_of(fresh) < gain_of(first), "a much louder song joined the album"
    assert fresh.headers["etag"] != first.headers["etag"]


# ---------------------------------------------------------------- measuring

def test_ten_requests_at_once_measure_each_song_once_and_a_restart_measures_none(upstream, mp4_cache, store,
                                                                                 tmp_path, monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    seen = measured(monkeypatch, delay=0.05)

    async def ten(each):
        answers = await asyncio.gather(*(each.get(url(f"song-{1 + i % 3}", ("fmp4", "mp4")[i % 2])) for i in range(10)))
        return [answer.headers.get("x-deadwax-level") for answer in answers]

    said_levels = run(ten)
    assert len(set(said_levels)) == 1 and said_levels[0].startswith("album ")
    assert sorted(seen) == sorted(set(seen)) and len(seen) == 3, "each song measured once"
    keys = kept_rows(store)
    assert len(keys) == 3 and all(key.startswith("s:") for key in keys)

    #? a restart: a new cache, the same database - nothing measured again, the same gain
    again = Mp4Cache(tmp_path / "after")
    again.levels.store = store
    monkeypatch.setattr(player_cache, "cache", again)
    seen.clear()
    answer = run(lambda each: each.get(url("song-2")))
    assert seen == [] and answer.headers["x-deadwax-level"] == said_levels[0]


def test_a_retag_is_measured_by_its_audio_so_only_the_copy_is_made_again(upstream, client, mp4_cache, store,
                                                                         tmp_path, monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    state, _ = upstream
    album = serving(state, files)
    seen = measured(monkeypatch)
    before = client.get(url("song-1", level="track"))
    assert len(seen) == 1
    album.modified["song-1"] = "Mon, 28 Sep 2026 09:00:00 GMT"
    later(mp4_cache)
    after = client.get(url("song-1", level="track"))
    assert len(seen) == 1, "STREAMINFO unchanged: no second measurement"
    assert after.headers["x-deadwax-level"] == before.headers["x-deadwax-level"]
    assert after.headers["etag"] != before.headers["etag"], "a new version: a new copy"


def test_a_song_with_no_md5_is_kept_by_its_version(upstream, client, mp4_cache, store, tmp_path, monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    data = bytearray(files["song-1"])
    data[26:42] = bytes(16)
    state, _ = upstream
    album = serving(state, {"song-1": bytes(data)})
    seen = measured(monkeypatch)
    assert "x-deadwax-level" in client.get(url("song-1", level="track")).headers
    assert [key[:2] for key in kept_rows(store)] == ["v:"]
    album.modified["song-1"] = "Mon, 28 Sep 2026 09:00:00 GMT"
    later(mp4_cache)
    client.get(url("song-1", level="track"))
    assert len(seen) == 2, "a retag measures it again: two songs of one length and no MD5 would share a key"


def test_past_the_wait_the_song_plays_as_it_is_once_and_the_measurement_carries_on(upstream, mp4_cache, store,
                                                                                   tmp_path, monkeypatch, caplog):
    """A slow measurement: the first answer, past LEVEL_WAIT_SECONDS, is the song as it is (the plain
    fragmented MP4, said once); the measurement carries on regardless, and the next answer is levelled."""
    np, sf, _ = libs()
    caplog.set_level(logging.INFO)
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    state, _ = upstream
    serving(state, files)
    monkeypatch.setattr(levels, "LEVEL_WAIT_SECONDS", 0.2)
    seen = measured(monkeypatch, delay=1.0)

    async def twice(each):
        first = await each.get(url("song-1", level="track"))
        await asyncio.sleep(1.5)
        second = await each.get(url("song-1", level="track"))
        plain = await each.get(url("song-1", level=None))
        return first, second, plain

    first, second, plain = run(twice)
    assert "x-deadwax-level" not in first.headers and first.content == flac_to_fmp4(files["song-1"])
    assert first.headers["etag"] == plain.headers["etag"]
    assert second.headers["x-deadwax-level"].startswith("track ")
    assert len(seen) == 1
    assert len(said(caplog, "plays as it is this time")) == 1


# ---------------------------------------------------------------- what can't be levelled

def test_what_cant_be_levelled_is_answered_exactly_as_without_a_level(upstream, client, mp4_cache, store, tmp_path,
                                                                      monkeypatch):
    np, sf, _ = libs()
    twenty = constant_flac(rate=44100, bps=20, blocks=(4096,) * 6)
    files = {"twenty": twenty, "mp3": b"\xff\xfb\x90\x00" + bytes(40000)}
    state, _ = upstream
    album = serving(state, files)
    album.types["mp3"] = "audio/mpeg"
    album.entries["mp3"].update(suffix="mp3", contentType="audio/mpeg")
    seen = measured(monkeypatch)
    for song in files:
        for wrap in ("mp4", "fmp4"):
            plain = client.get(url(song, wrap, None))
            asked = client.get(url(song, wrap, "album"))
            assert (asked.status_code, asked.content, asked.headers.get("etag")) == (
                plain.status_code, plain.content, plain.headers.get("etag"))
            assert "x-deadwax-level" not in asked.headers
    assert seen == [] and kept_rows(store) == []


def test_without_numpy_or_soundfile_a_level_is_ignored_and_said_once(upstream, client, mp4_cache, store, tmp_path,
                                                                     monkeypatch, caplog):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    state, _ = upstream
    serving(state, files)
    monkeypatch.setattr(levels, "missing_libraries", lambda: "numpy")
    plain = client.get(url("song-1", level=None))
    for _ in range(2):
        asked = client.get(url("song-1"))
        assert (asked.content, asked.headers["etag"]) == (plain.content, plain.headers["etag"])
    assert len(said(caplog, "can't be levelled on this server - numpy")) == 1
    answer = client.get("/deadwax/navidrome/level/song-1?level=album").json()
    assert (answer["state"], answer["why"]) == ("not_levelled", levels.NO_LIBRARIES)


def test_with_no_cache_folder_nothing_is_levelled(upstream, client, tmp_path, monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    state, _ = upstream
    serving(state, files)
    blocked = tmp_path / "a-file"
    blocked.write_text("not a folder")
    monkeypatch.setattr(player_cache, "cache", Mp4Cache(blocked))
    asked = client.get(url("song-1", "mp4"))
    assert asked.content == files["song-1"] and "x-deadwax-level" not in asked.headers
    answer = client.get("/deadwax/navidrome/level/song-1?level=track").json()
    assert (answer["state"], answer["why"]) == ("not_levelled", levels.NO_CACHE)


@pytest.mark.parametrize("query", ["format=mp3&wrap=mp4", "format=raw", "format=mp3", "wrap=fmp4", ""],
                         ids=["a transcode in an MP4", "no wrap", "a transcode", "no format", "nothing"])
def test_a_level_needs_the_file_as_it_is_and_a_wrap(upstream, client, query):
    _, seen = upstream
    response = client.get(f"/deadwax/navidrome/stream/song-1?{query}&level=album")
    assert response.status_code == 400
    assert response.json()["detail"].startswith("level needs format=raw and wrap=mp4 or wrap=fmp4")
    assert seen == []


@pytest.mark.parametrize("value", ["song", "off", "", "ALBUM"])
def test_any_other_level_is_refused(upstream, client, value):
    _, seen = upstream
    assert client.get(f"/deadwax/navidrome/stream/song-1?format=raw&wrap=fmp4&level={value}").status_code == 422
    assert client.get(f"/deadwax/navidrome/scrub/song-1?at=1&level={value}").status_code == 422
    assert client.get(f"/deadwax/navidrome/level/song-1?level={value}").status_code == 422
    assert client.get("/deadwax/navidrome/scrub/song-1?at=1&gain=3").status_code == 422
    assert seen == []


# ---------------------------------------------------------------- the turntable's windows

def test_a_levelled_songs_window_is_cut_from_its_levelled_copy(upstream, client, mp4_cache, store, tmp_path):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 3,))
    state, _ = upstream
    serving(state, files)
    copy = client.get(url("song-1", "mp4", "track"))
    window = client.get("/deadwax/navidrome/scrub/song-1?at=1&seconds=1&level=track")
    first, samples, rate = map(int, window.headers["x-deadwax-window"].split("/"))
    cut, _ = sf.read(io_of(window.content), dtype="int32", always_2d=True)
    whole, _ = decoded(sf, copy.content)
    assert rate == 44100 and len(cut) == samples
    assert np.array_equal(cut >> 8, whole[first:first + samples])

    plain_window = client.get("/deadwax/navidrome/scrub/song-1?at=1&seconds=1")
    plain_cut, _ = sf.read(io_of(plain_window.content), dtype="int32", always_2d=True)
    plain_first = int(plain_window.headers["x-deadwax-window"].split("/")[0])
    own, _ = sf.read(io_of(files["song-1"]), dtype="int32", always_2d=True)
    assert np.array_equal(plain_cut, own[plain_first:plain_first + len(plain_cut)]), "without a level, today's window"


def io_of(data: bytes):
    import io
    return io.BytesIO(data)


# ---------------------------------------------------------------- Info's route and the album page's

def test_infos_route_says_what_deadwax_would_level_a_song_at(upstream, client, mp4_cache, store, tmp_path,
                                                             monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    files["mp3"] = b"\xff\xfb\x90\x00" + bytes(40000)
    files["twenty"] = constant_flac(rate=44100, bps=20, blocks=(4096,) * 6)
    state, _ = upstream
    album = serving(state, files)
    album.types["mp3"] = "audio/mpeg"
    album.entries["mp3"].update(suffix="mp3", contentType="audio/mpeg")
    seen = measured(monkeypatch)

    def ask(song, level="album"):
        return client.get(f"/deadwax/navidrome/level/{song}?level={level}").json()

    fresh = ask("song-2")
    assert (fresh["state"], fresh["songs"], fresh["measured_songs"]) == ("unmeasured", 3, 0)
    assert seen == [], "Info's route never measures"
    assert ask("mp3")["state"] == "not_levelled" and ask("mp3")["why"] == levels.NOT_FLAC
    assert ask("twenty")["why"] == levels.UNREADABLE

    played = client.get(url("song-2"))
    answer = ask("song-2")
    assert answer["state"] == "measured" and answer["gain_db"] == gain_of(played)
    assert answer["songs"] == answer["measured_songs"] == 3
    assert answer["wanted_db"] == pytest.approx(loudness.REFERENCE_LUFS - answer["loudness_lufs"], abs=0.011)
    track = ask("song-2", "track")
    assert track["state"] == "measured" and track["songs"] == 1


def test_infos_route_asks_whether_the_song_is_theirs(upstream, client, monkeypatch):
    async def not_theirs(request, song_id):
        raise NavidromeError("not found", status=404)

    monkeypatch.setattr(navidrome_routes, "_theirs", not_theirs)
    assert client.get("/deadwax/navidrome/level/song-1?level=album").status_code == 404
    assert client.get(url("song-1")).status_code == 404


def test_infos_route_says_an_album_is_being_measured(upstream, mp4_cache, store, tmp_path, monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    measured(monkeypatch, delay=0.5)

    async def during(each):
        warmed = await each.post("/deadwax/navidrome/level/album/album-1")
        await asyncio.sleep(0.2)
        middle = (await each.get("/deadwax/navidrome/level/song-1?level=album")).json()
        while mp4_cache.levels._albums:
            await asyncio.sleep(0.1)
        after = (await each.get("/deadwax/navidrome/level/song-1?level=album")).json()
        return warmed, middle, after

    warmed, middle, after = run(during)
    assert (warmed.status_code, warmed.json()) == (202, {"state": "measuring"})
    assert middle["state"] == "measuring" and middle["songs"] == 3 and middle["measured_songs"] < 3
    assert after["state"] == "measured"


def test_an_album_page_measures_its_album_once_and_none_while_another_is(upstream, mp4_cache, store, tmp_path,
                                                                         monkeypatch):
    np, sf, _ = libs()
    _, first = cd_album(np, sf, tmp_path, lengths=(44100,) * 2, seed=5)
    state, _ = upstream
    album = serving(state, first)

    def handle(request):
        #? a second album Navidrome has, so the asker's look at it is answered
        if request.url.path.endswith("getAlbum") and request.url.params.get("id") == "album-2":
            return httpx.Response(200, json=ok(album={"id": "album-2", "name": "Other", "song": []}))
        return album.handle(request)

    state["handler"] = handle
    seen = measured(monkeypatch, delay=0.3)

    async def warm(each):
        one = await each.post("/deadwax/navidrome/level/album/album-1")
        two = await each.post("/deadwax/navidrome/level/album/album-1")
        #? another album opened while album-1 is being measured (its gate taken - only once it has looked at
        #? its songs and found some to measure): dropped - a play measures on demand anyway
        while not mp4_cache.levels._gates()[0].locked():
            await asyncio.sleep(0.01)
        other = await each.post("/deadwax/navidrome/level/album/album-2")
        while mp4_cache.levels._gates()[0].locked():
            await asyncio.sleep(0.05)
        return one.json(), two.json(), other.json()

    one, two, other = run(warm)
    assert (one, two, other) == ({"state": "measuring"}, {"state": "measuring"}, {"state": "busy"})
    assert len(seen) == 2 and len(set(seen)) == 2


def test_an_album_page_asks_navidrome_for_the_album_as_the_asker_first(upstream, client, mp4_cache, tmp_path,
                                                                        monkeypatch):
    """An album Navidrome won't give the asker is its 404, and nothing is measured."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100,))
    state, seen = upstream
    serving(state, files)
    measuring = measured(monkeypatch)
    response = client.post("/deadwax/navidrome/level/album/al-9")
    assert response.status_code == 404
    asked = [request for request in seen if request.url.path.endswith("getAlbum")]
    assert [request.url.params.get("id") for request in asked] == ["al-9"]
    assert measuring == [] and mp4_cache.levels._albums == {}


# ---------------------------------------------------------------- Part B: a download filed

def test_a_filed_flac_album_is_measured_and_its_first_levelled_play_measures_nothing(upstream, client, mp4_cache,
                                                                                    store, tmp_path, monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    library = tmp_path / "library" / "Artist" / "Album (2020)"
    library.mkdir(parents=True)
    operations = []
    for name, data in files.items():
        (library / f"{name}.flac").write_bytes(data)
        operations.append({"source": "x", "target": str(library / f"{name}.flac")})
    (library / "cover.jpg").write_bytes(b"\xff\xd8")
    operations.append({"source": "y", "target": str(library / "cover.jpg"), "companion": True})
    seen = measured(monkeypatch)

    async def filed():
        task = poller._measure_later({"plan": {"operations": operations}}, store)
        return await task

    assert asyncio.run(filed()) == 3
    keys = kept_rows(store)
    assert keys == sorted(loudness.audio_key(data[8:42], None) for data in files.values())
    assert len(seen) == 3
    seen.clear()

    state, _ = upstream
    serving(state, files)
    assert client.get(url("song-1")).headers["x-deadwax-level"].startswith("album ")
    assert seen == [], "measured at filing - by the same key Navidrome's copy has"


@pytest.mark.parametrize("mode", ["copy", "dry_run"])
def test_the_poller_measures_what_it_files_and_nothing_in_a_dry_run(tmp_path, monkeypatch, mode):
    """Part B through the poller itself: a download organized for real has its FLAC songs measured in the
    background, keyed by the STREAMINFO they carry - the very key Navidrome's copy of them has, the tags the
    organizer wrote notwithstanding. A dry run files nothing, and measures nothing."""
    np, sf, _ = libs()
    from src.config import Config
    from test_poller import FakeSlskd, _all_done, make_store, seed_job

    _, files = cd_album(np, sf, tmp_path, lengths=(44100, 44100))
    downloads = tmp_path / "downloads" / "album"
    downloads.mkdir(parents=True)
    for name, data in zip(("01.flac", "02.flac"), files.values()):
        (downloads / name).write_bytes(data)
    monkeypatch.setattr(Config, "SLSKD_DOWNLOAD_PATH", str(tmp_path / "downloads"))
    monkeypatch.setattr(Config, "LIBRARY_PATH", str(tmp_path / "music"))
    monkeypatch.setattr(Config, "ORGANIZE_MODE", mode)
    monkeypatch.setattr(Config, "FETCH_LYRICS", "off")
    kept = make_store(tmp_path)
    seed_job(kept)
    seen = measured(monkeypatch)

    async def poll():
        await poller.poll_downloads_once(FakeSlskd(_all_done()), kept, {})
        await asyncio.gather(*list(poller._measure_tasks))

    asyncio.run(poll())
    if mode == "dry_run":
        assert seen == [] and kept_rows(kept) == []
        return
    filed = sorted((tmp_path / "music").rglob("*.flac"))
    assert len(filed) == 2 and all(path.read_bytes() != data for path, data in zip(filed, files.values())), "tagged"
    assert kept_rows(kept) == sorted(loudness.audio_key(data[8:42], None) for data in files.values())
    assert sorted(seen) == sorted(path.name for path in filed)


def test_a_carry_on_from_the_song_as_it_is_stays_on_it_once_its_level_is_in(upstream, mp4_cache, store, tmp_path,
                                                                           monkeypatch):
    """Safari's element played a levelled URL's first answer as the song as it is (its measuring took past the
    wait): its next range - Safari sends no If-Range - comes from that same MP4 even once the level is known,
    never the levelled copy's bytes under another length. A fresh start then gets the levelled copy."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    state, _ = upstream
    serving(state, files)
    monkeypatch.setattr(levels, "LEVEL_WAIT_SECONDS", 0.2)
    measured(monkeypatch, delay=1.0)

    async def safari(each):
        probe = await each.get(url("song-1", "mp4", "track"), headers={"Range": "bytes=0-1"})
        await asyncio.sleep(1.5)
        rest = await each.get(url("song-1", "mp4", "track"), headers={"Range": "bytes=2-"})
        mp4_cache.clock = (lambda now: lambda: now)(mp4_cache.clock() + player_cache.VERSION_SECONDS + 1)
        fresh = await each.get(url("song-1", "mp4", "track"), headers={"Range": "bytes=0-1"})
        return probe, rest, fresh

    probe, rest, fresh = run(safari)
    plain = flac_to_mp4(files["song-1"])
    assert "x-deadwax-level" not in probe.headers and probe.content == plain[:2]
    assert (rest.status_code, rest.content, rest.headers["etag"]) == (206, plain[2:], probe.headers["etag"])
    assert fresh.headers["x-deadwax-level"].startswith("track ") and fresh.headers["etag"] != probe.headers["etag"]


def test_a_song_asked_by_song_from_everywhere_at_once_is_measured_once(upstream, mp4_cache, store, tmp_path,
                                                                     monkeypatch):
    """By song, no album's measurement in between: the stream, the element, Info and a window all asking for
    one song at once wait on ONE measurement of it (single flight per song)."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    state, _ = upstream
    serving(state, files)
    seen = measured(monkeypatch, delay=0.3)

    async def everywhere(each):
        asks = [each.get(url("song-1", wrap, "track")) for wrap in ("fmp4", "mp4", "fmp4", "mp4")]
        asks.append(each.get("/deadwax/navidrome/scrub/song-1?at=0.5&seconds=1&level=track"))
        answers = await asyncio.gather(*asks)
        return [answer.headers.get("x-deadwax-level") for answer in answers[:4]]

    said_levels = run(everywhere)
    assert len(set(said_levels)) == 1 and said_levels[0].startswith("track ")
    assert len(seen) == 1, "one measurement for everyone"


def test_a_song_asked_by_song_while_its_album_is_measured_is_measured_once(upstream, mp4_cache, store, tmp_path,
                                                                         monkeypatch):
    """A song asked for by song while its album is being measured by album (a playlist and the album page at
    once): the album's measurement and the song's are one measurement of that song."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    seen = measured(monkeypatch, delay=0.3)

    async def both(each):
        return await asyncio.gather(each.get(url("song-2", "fmp4", "album")), each.get(url("song-1", "fmp4", "track")),
                                    each.get(url("song-1", "mp4", "track")))

    answers = run(both)
    assert [answer.headers["x-deadwax-level"].split()[0] for answer in answers] == ["album", "track", "track"]
    assert sorted(seen) == sorted(set(seen)) and len(seen) == 3, "each of the album's three songs measured once"


# ---------------------------------------------------------------- waits, and albums looked at in part (after review)

def test_a_measured_album_never_waits_behind_another_being_measured(upstream, mp4_cache, store, tmp_path, monkeypatch):
    """Every song of album A measured, and another album holding the one-album gate (its page opened): A's
    next song is levelled at once - the gate is taken only to measure."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    monkeypatch.setattr(levels, "LEVEL_WAIT_SECONDS", 0.5)

    async def go(each):
        first = await each.get(url("song-1"))
        gate, _ = mp4_cache.levels._gates()
        await gate.acquire()
        try:
            began = time.monotonic()
            second = await each.get(url("song-2"))
            took = time.monotonic() - began
        finally:
            gate.release()
        return first, second, took

    first, second, took = run(go)
    assert second.headers["x-deadwax-level"] == first.headers["x-deadwax-level"]
    assert took < 0.4


def test_a_gain_kept_from_before_is_answered_at_once_while_it_is_worked_out_again(upstream, mp4_cache, store,
                                                                                 tmp_path, monkeypatch):
    """Past VERSION_SECONDS a song's gain is worked out again - and when that is slow (Navidrome slow to list
    the album), the one kept is answered within STALE_WAIT_SECONDS, not after the whole wait."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    monkeypatch.setattr(levels, "LEVEL_WAIT_SECONDS", 5)
    monkeypatch.setattr(levels, "STALE_WAIT_SECONDS", 0.2)

    async def go(each):
        first = await each.get(url("song-1"))
        later(mp4_cache)
        real = mp4_cache.albums._listing

        async def slow(album_id):
            await asyncio.sleep(1.0)
            return await real(album_id)

        mp4_cache.albums._listing = slow
        began = time.monotonic()
        again = await each.get(url("song-1"))
        return first, again, time.monotonic() - began

    first, again, took = run(go)
    assert again.headers["x-deadwax-level"] == first.headers["x-deadwax-level"]
    assert took < 0.8


def flaky_looks(monkeypatch, song: str, times: int):
    """`song`'s STREAMINFO not read in time (CannotPlan) the first `times` times it is looked at."""
    from src.album_context import CannotPlan

    real = levels.Levels._song
    failed = []

    async def flaky(self, song_id):
        if song_id == song and len(failed) < times:
            failed.append(song_id)
            raise CannotPlan("timed out")
        return await real(self, song_id)

    monkeypatch.setattr(levels.Levels, "_song", flaky)
    return failed


def test_an_album_one_of_whose_songs_couldnt_be_looked_at_just_now_is_never_levelled_in_part(
        upstream, mp4_cache, store, tmp_path, monkeypatch):
    """A song of the album whose look fails once is looked at again at once, and the album gets ONE gain;
    one that fails again leaves the song asked unlevelled this time - never a gain pooled from part of the
    album, which would be another gain a moment later."""
    np, sf, _ = libs()
    _, quiet = cd_album(np, sf, tmp_path, lengths=(44100 * 2,) * 2, level=0.05, seed=1)
    _, loud = cd_album(np, sf, tmp_path, lengths=(44100 * 2,), level=0.9, seed=2)
    files = {"song-1": quiet["song-1"], "song-2": quiet["song-2"], "song-3": loud["song-1"]}
    state, _ = upstream
    serving(state, files)

    flaky_looks(monkeypatch, "song-3", 1)

    async def three(each):
        return [await each.get(url(song)) for song in files]

    gains = [answer.headers.get("x-deadwax-level") for answer in run(three)]
    assert len(set(gains)) == 1 and gains[0].startswith("album "), gains

    mp4_cache.levels._gains.clear()
    failed = flaky_looks(monkeypatch, "song-3", 2)
    first = run(lambda each: each.get(url("song-1")))
    assert len(failed) == 2 and "x-deadwax-level" not in first.headers
    assert run(lambda each: each.get(url("song-1"))).headers["x-deadwax-level"] == gains[0]


def test_a_song_whose_measuring_failed_just_now_leaves_its_album_unlevelled_this_time(upstream, mp4_cache, store,
                                                                                    tmp_path, monkeypatch):
    """One song of the album not measured just now (its download broke off, twice): the song asked plays as
    it is this time, not at a gain pooled from the rest - and once it is measured, every song gets one gain."""
    np, sf, _ = libs()
    _, quiet = cd_album(np, sf, tmp_path, lengths=(44100 * 2,) * 2, level=0.05, seed=1)
    _, loud = cd_album(np, sf, tmp_path, lengths=(44100 * 2,), level=0.9, seed=2)
    files = {"song-1": quiet["song-1"], "song-2": quiet["song-2"], "song-3": loud["song-1"]}
    state, _ = upstream
    serving(state, files)
    real = levels.Levels._download
    broke = []

    async def flaky(self, song, path):
        if song.song_id == "song-3" and len(broke) < 2:
            broke.append(1)
            return False
        return await real(self, song, path)

    monkeypatch.setattr(levels.Levels, "_download", flaky)

    async def go(each):
        first = await each.get(url("song-1"))
        rest = [await each.get(url(song)) for song in files]
        return first, rest

    first, rest = run(go)
    assert len(broke) == 2 and "x-deadwax-level" not in first.headers
    gains = {answer.headers["x-deadwax-level"] for answer in rest}
    assert len(gains) == 1


def test_while_an_album_is_measured_its_other_songs_are_answered_at_once(upstream, mp4_cache, store, tmp_path,
                                                                        monkeypatch):
    """A request that waited the whole wait for its album: the album's other songs, asked while it is still
    being measured, are answered as they are at once - not after a wait each - and once it is measured,
    levelled."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    monkeypatch.setattr(levels, "LEVEL_WAIT_SECONDS", 0.3)
    measured(monkeypatch, delay=1.5)

    async def go(each):
        first = await each.get(url("song-1"))
        began = time.monotonic()
        second = await each.get(url("song-2", "mp4"))
        took = time.monotonic() - began
        while mp4_cache.levels._albums:
            await asyncio.sleep(0.05)
        third = await each.get(url("song-3"))
        return first, second, took, third

    first, second, took, third = run(go)
    assert "x-deadwax-level" not in first.headers and "x-deadwax-level" not in second.headers
    assert took < 0.25
    assert third.headers["x-deadwax-level"].startswith("album ")
    assert mp4_cache.levels._overdue == set()


def test_a_hi_res_copy_waits_less_for_its_level_so_its_make_fits_the_pages_wait(upstream, mp4_cache, store, tmp_path,
                                                                              monkeypatch):
    """A copy resampled as well as levelled waits LEVEL_WAIT_HIRES_SECONDS for its level, not
    LEVEL_WAIT_SECONDS: its make needs the rest of the page's 60 s. Past it, the song resampled as it is."""
    np, sf, _ = libs()
    state, _ = upstream
    serving(state, {"song-1": write_flac(sf, tmp_path / "hi.flac", music(np, 192000, 96001, level=0.5),
                                         192000).read_bytes()})
    monkeypatch.setattr(levels, "LEVEL_WAIT_SECONDS", 30)
    monkeypatch.setattr(levels, "LEVEL_WAIT_HIRES_SECONDS", 0.2)
    measured(monkeypatch, delay=1.5)

    async def go(each):
        began = time.monotonic()
        answer = await each.get(url("song-1", "fmp4", "track", capped=True))
        return answer, time.monotonic() - began

    answer, took = run(go)
    assert "x-deadwax-level" not in answer.headers and answer.headers["x-deadwax-resampled"] == "192000-48000"
    assert took < 1.4


@pytest.mark.parametrize("wrap", ["mp4", "fmp4"])
def test_info_and_the_turntable_follow_a_song_answered_as_it_is(upstream, mp4_cache, store, tmp_path, monkeypatch,
                                                                wrap):
    """A song answered as it is (its level not to be had in time) - to Safari's element, or the gapless stream:
    Info's route says so - not the gain measured since - and its turntable windows are cut as without the level,
    what is heard. A new play of it is levelled, and from then on Info and the windows are too."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 3,))
    state, _ = upstream
    serving(state, files)
    monkeypatch.setattr(levels, "LEVEL_WAIT_SECONDS", 0.2)
    measured(monkeypatch, delay=1.0)
    scrub = "/deadwax/navidrome/scrub/song-1?at=1&seconds=1"

    async def go(each):
        first = await each.get(url("song-1", wrap, level="track"))
        await asyncio.sleep(1.5)
        info = (await each.get("/deadwax/navidrome/level/song-1?level=track")).json()
        window = await each.get(scrub + "&level=track")
        plain_window = await each.get(scrub)
        again = await each.get(url("song-1", level="track"))
        info_after = (await each.get("/deadwax/navidrome/level/song-1?level=track")).json()
        window_after = await each.get(scrub + "&level=track")
        return first, info, window, plain_window, again, info_after, window_after

    first, info, window, plain_window, again, info_after, window_after = run(go)
    assert "x-deadwax-level" not in first.headers
    assert info["state"] == "plain" and info["gain_db"] is None
    assert window.content == plain_window.content
    assert again.headers["x-deadwax-level"].startswith("track ")
    assert info_after["state"] == "measured" and info_after["gain_db"] == gain_of(again)
    assert window_after.content != plain_window.content


# ---------------------------------------------------------------- measuring no more than once

def test_a_row_of_another_algorithm_is_measured_again_and_replaced(upstream, client, mp4_cache, store, tmp_path,
                                                                  monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    state, _ = upstream
    serving(state, files)
    key = loudness.audio_key(files["song-1"][8:42], None)
    old = levels._row(key, loudness.Measurement(peak=0.5, histogram=[(100, 5)], blocks=5, seconds=2.0))
    asyncio.run(store.loudness_put({**old, "algorithm": loudness.ALGORITHM_VERSION - 1}))
    seen = measured(monkeypatch)
    assert client.get(url("song-1", level="track")).headers["x-deadwax-level"].startswith("track ")
    assert len(seen) == 1
    with sqlite3.connect(store.path) as connection:
        assert connection.execute("SELECT algorithm FROM loudness").fetchall() == [(loudness.ALGORITHM_VERSION,)]


def test_a_filed_song_measured_already_is_not_measured_again(store, tmp_path, monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100,) * 2)
    paths = []
    for name, data in files.items():
        path = tmp_path / f"{name}.flac"
        path.write_bytes(data)
        paths.append(path)
    seen = measured(monkeypatch)
    assert asyncio.run(levels.measure_filed(store, paths)) == 2
    assert asyncio.run(levels.measure_filed(store, paths)) == 0
    assert len(seen) == 2


def test_a_song_that_cant_be_measured_is_tried_once(upstream, client, mp4_cache, store, tmp_path, monkeypatch):
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 2,))
    state, _ = upstream
    serving(state, files)
    tried = []

    def cannot(path, *args, **kwargs):
        tried.append(path)
        raise loudness.CannotMeasure("libsndfile couldn't decode all of it")

    monkeypatch.setattr(levels.loudness, "measure_file", cannot)
    for _ in range(2):
        answer = client.get(url("song-1", level="track"))
        assert "x-deadwax-level" not in answer.headers
    assert len(tried) == 1
    info = client.get("/deadwax/navidrome/level/song-1?level=track").json()
    assert info["state"] == "not_levelled" and "decode" in info["why"]


# ---------------------------------------------------------------- found in the second review

def failing_looks(monkeypatch, song: str, status: int):
    """`song`'s look answered by Navidrome with `status`, every time."""
    real = levels.Levels._song

    async def failing(self, song_id):
        if song_id == song:
            raise NavidromeError("Navidrome said no", status=status)
        return await real(self, song_id)

    monkeypatch.setattr(levels.Levels, "_song", failing)


@pytest.mark.parametrize("status", [404, 500])
def test_a_song_navidrome_cant_serve_is_left_out_and_its_album_is_levelled(upstream, mp4_cache, store, tmp_path,
                                                                           monkeypatch, status):
    """A song whose file is gone or unreadable on Navidrome's side (its look answered with an error that
    stays) is left out of the album's pool like one deadwax can't read - the rest of the album gets one gain,
    and Info says so - never the whole album unlevelled, with Info blaming a measurement."""
    np, sf, _ = libs()
    _, quiet = cd_album(np, sf, tmp_path, lengths=(44100 * 2,) * 2, level=0.05, seed=1)
    _, loud = cd_album(np, sf, tmp_path, lengths=(44100 * 2,), level=0.9, seed=2)
    files = {"song-1": quiet["song-1"], "song-2": quiet["song-2"], "song-3": loud["song-1"]}
    state, _ = upstream
    serving(state, files)
    failing_looks(monkeypatch, "song-3", status)

    async def go(each):
        answers = [await each.get(url(song)) for song in ("song-1", "song-2", "song-1")]
        info = (await each.get("/deadwax/navidrome/level/song-1?level=album")).json()
        return answers, info

    answers, info = run(go)
    gains = {answer.headers.get("x-deadwax-level") for answer in answers}
    assert len(gains) == 1 and None not in gains, gains
    assert (info["state"], info["songs"], info["gain_db"]) == ("measured", 2, gain_of(answers[0]))


def test_a_song_navidrome_says_is_busy_is_looked_at_again_not_left_out(upstream, mp4_cache, store, tmp_path,
                                                                      monkeypatch):
    """A 503 (or a 429) passes in a moment: the album isn't levelled from part of itself this time."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    failing_looks(monkeypatch, "song-3", 503)
    assert "x-deadwax-level" not in run(lambda each: each.get(url("song-1"))).headers


def test_album_pages_opened_one_after_another_measure_only_the_first(upstream, mp4_cache, store, tmp_path,
                                                                    monkeypatch):
    """A second album page opened while the first album's songs are still being LISTED (before its gate is
    taken) is dropped as busy - it never queues a whole album that a play would then wait behind."""
    np, sf, _ = libs()
    _, first = cd_album(np, sf, tmp_path, lengths=(44100,) * 2, seed=5)
    state, _ = upstream
    album = serving(state, first)

    def handle(request):
        if request.url.path.endswith("getAlbum") and request.url.params.get("id") == "album-2":
            return httpx.Response(200, json=ok(album={"id": "album-2", "name": "Other", "song": []}))
        return album.handle(request)

    state["handler"] = handle
    seen = measured(monkeypatch)
    real = levels.Levels._album_songs

    async def slow(self, album_id):
        #? a NAS's Navidrome answering the album's looks
        await asyncio.sleep(0.3)
        return await real(self, album_id)

    monkeypatch.setattr(levels.Levels, "_album_songs", slow)

    async def warm(each):
        one = await each.post("/deadwax/navidrome/level/album/album-1")
        two = await each.post("/deadwax/navidrome/level/album/album-2")
        locked = mp4_cache.levels._gates()[0].locked()
        while mp4_cache.levels._albums:
            await asyncio.sleep(0.05)
        return one.json(), two.json(), locked

    one, two, locked = run(warm)
    assert not locked, "the second page was opened before the first album's gate was taken"
    assert (one, two) == ({"state": "measuring"}, {"state": "busy"})
    assert len(seen) == 2


def test_a_levelled_copy_too_big_to_make_goes_as_off_would_send_it(upstream, client, mp4_cache, store, tmp_path,
                                                                   monkeypatch):
    """A long CD song that fits as a plain MP4 but whose 24-bit levelled copy (about 1.5 times it) is over the
    size a song is held in memory to repackage: answered exactly as Off answers it - the plain MP4 to Safari,
    not the bare FLAC a refused copy would be; the plain fragmented MP4; the plain window - with nothing
    measured for it, and Info saying why."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 4,))
    state, _ = upstream
    serving(state, files)
    mp4_cache.wrap_max_bytes = int(len(files["song-1"]) * 1.3)
    seen = measured(monkeypatch)

    for wrap in ("mp4", "fmp4"):
        off = client.get(url("song-1", wrap, level=None))
        for level in ("album", "track"):
            on = client.get(url("song-1", wrap, level=level))
            assert (on.status_code, on.headers["content-type"], on.headers["etag"]) == \
                (off.status_code, off.headers["content-type"], off.headers["etag"]), (wrap, level)
            assert on.content == off.content and "x-deadwax-level" not in on.headers
    off_window = client.get("/deadwax/navidrome/scrub/song-1?at=1&seconds=1")
    on_window = client.get("/deadwax/navidrome/scrub/song-1?at=1&seconds=1&level=album")
    assert on_window.status_code == 200 and on_window.content == off_window.content
    assert seen == [], "nothing is measured for a copy that can't be made"
    info = client.get("/deadwax/navidrome/level/song-1?level=album").json()
    assert info["state"] == "not_levelled" and "levelled it would be about" in info["why"]


def test_a_levelled_cd_song_needs_room_on_the_disk_for_its_bigger_copy(upstream, client, mp4_cache, store, tmp_path,
                                                                      monkeypatch):
    """Room on the disk is judged at the copy's size, not the source's: a 16-bit song's 24-bit levelled copy
    is about 1.5 times it, and a disk with room for the source's copies but not for those isn't written to."""
    from test_player_cache import a_disk

    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path, lengths=(44100 * 4,))
    state, _ = upstream
    serving(state, files)
    size = len(files["song-1"])
    a_disk(monkeypatch, mp4_cache, player_cache.DISK_SPARE_BYTES + player_cache.MAKE_ROOM_FACTOR * size * 13 // 10)

    answer = client.get(url("song-1", level="track"))
    assert answer.status_code == 503 and "short of space" in answer.text
    assert not list(mp4_cache.directory.rglob("*.mp4"))


def test_infos_route_never_pools_part_of_an_album(upstream, client, mp4_cache, store, tmp_path, monkeypatch):
    """Info's route, like the stream's, gives an album gain only from the whole album: with a song of it not
    looked at just now, it says the album isn't measured - not a gain pooled from the rest."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    for song in files:
        client.get(url(song))
    mp4_cache.levels._gains.clear()
    flaky_looks(monkeypatch, "song-3", 100)
    info = client.get("/deadwax/navidrome/level/song-1?level=album").json()
    assert info["state"] != "measured" and info["gain_db"] is None


def test_an_album_keeps_no_resample_room_where_nothing_can_be_resampled(monkeypatch):
    """_album_reserve(): the 3 dB room for a hi-res song only where deadwax can resample it."""
    from types import SimpleNamespace

    def song(rate, bits):
        return SimpleNamespace(info=SimpleNamespace(sample_rate=rate, bits_per_sample=bits))

    album = [song(44100, 16), song(96000, 24)]
    monkeypatch.setattr(levels.resample, "missing_libraries", lambda: None)
    assert levels._album_reserve(album) == resample.HEADROOM_DB
    assert levels._album_reserve(album[:1]) == 0.0
    monkeypatch.setattr(levels.resample, "missing_libraries", lambda: "soxr")
    assert levels._album_reserve(album) == 0.0


def test_a_songs_gain_is_worked_out_once_for_requests_at_once(upstream, mp4_cache, store, tmp_path, monkeypatch):
    """Single flight on the gain itself: requests for one song at one level at once resolve it once."""
    np, sf, _ = libs()
    _, files = cd_album(np, sf, tmp_path)
    state, _ = upstream
    serving(state, files)
    real = levels.Levels._resolve_now
    resolved = []

    async def counted(self, song, *args):
        resolved.append(song.song_id)
        return await real(self, song, *args)

    monkeypatch.setattr(levels.Levels, "_resolve_now", counted)

    async def at_once(each):
        return await asyncio.gather(*(each.get(url("song-1")) for _ in range(4)))

    answers = run(at_once)
    assert len({answer.headers["x-deadwax-level"] for answer in answers}) == 1
    assert resolved == ["song-1"]
