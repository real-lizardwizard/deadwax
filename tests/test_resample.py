"""
Hi-res songs resampled to 48 kHz or 44.1 kHz for the player (src/resample.py): what is touched,
the album's grid, and the audio - that nothing below 20 kHz changes but the headroom's one gain,
that nothing clips, and above all that songs resampled one at a time with their neighbours' samples
join into exactly what one resample of the whole album gives. And the file written: never empty, and
a disk that fills while it is written is said to be full.

The audio tests need numpy, soxr and soundfile, and skip without them - except in CI, where the
last test here fails instead, so they can never be skipped there without anybody noticing. Every
FLAC is written here with soundfile, or with the muxer tests' own encoder: no binary files.
"""

import errno
import io
import math
import os
import random
import struct
import sys
import threading
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import resample  # noqa: E402
from src.flac_mp4 import _read_metadata, _skip_id3v2  # noqa: E402
from src.resample import (CannotResample, ResamplePlan, Stopped, album_phase, next_phase,  # noqa: E402
                          output_count, output_rate)
from test_flac_mp4 import crc16, encode, frame_header  # noqa: E402

FULL = float(1 << 23)
TOP, BOTTOM = (1 << 23) - 1, -(1 << 23)

#? what every resampled song is scaled by: HEADROOM_DB down
GAIN = 10 ** (-resample.HEADROOM_DB / 20)


def libraries():
    """numpy, soundfile and soxr - or this test is skipped (see test_the_audio_libraries_are_there_in_ci)."""
    return pytest.importorskip("numpy"), pytest.importorskip("soundfile"), pytest.importorskip("soxr")


# ---------------------------------------------------------------- what is touched

@pytest.mark.parametrize("source, out", [(88200, 44100), (176400, 44100), (352800, 44100),
                                         (96000, 48000), (192000, 48000), (384000, 48000)])
@pytest.mark.parametrize("bits", [16, 24])
def test_the_rates_resampled_and_what_to(source, out, bits):
    assert output_rate(source, 48000, bits) == out


@pytest.mark.parametrize("source", [44100, 48000, 32000, 22050, 64000, 50000, 100000, 128000])
def test_anything_else_is_sent_as_it_is(source):
    """At or below the cap untouched, bit for bit; above it only a whole ratio of 44.1 or 48 kHz."""
    assert output_rate(source, 48000, 24) is None


@pytest.mark.parametrize("bits", [8, 12, 20, 32])
def test_only_16_and_24_bit_songs_are_resampled(bits):
    """libsndfile 1.2.2 can't open a 20- or 32-bit FLAC at all."""
    assert output_rate(192000, 48000, bits) is None


def test_original_resamples_nothing():
    assert output_rate(192000, None, 24) is None


def test_rates_are_said_as_people_say_them():
    assert [resample.khz(r) for r in (192000, 44100, 176400, 48000, 352800)] == [
        "192 kHz", "44.1 kHz", "176.4 kHz", "48 kHz", "352.8 kHz"]


# ---------------------------------------------------------------- the album's grid

@pytest.mark.parametrize("ratio", [2, 4, 8])
def test_the_phase_from_the_songs_before_is_the_phase_the_songs_hand_on(ratio):
    """album_phase() of the running total is what next_phase() carries from song to song - the
    NEGATIVE of the total: the other sign joined at -14.7 dB, one sample long."""
    rng = random.Random(ratio)
    phase, earlier = 0, 0
    for _ in range(200):
        assert album_phase(earlier, ratio) == phase
        n = rng.randrange(1, 10 ** 6)
        phase, earlier = next_phase(phase, n, ratio), earlier + n


@pytest.mark.parametrize("ratio", [2, 4, 8])
def test_the_songs_counts_add_up_to_the_whole_albums(ratio):
    """Each song's count on the grid, summed, is one resample of the whole album's: ceil(N / ratio)."""
    rng = random.Random(ratio + 10)
    for _ in range(100):
        lengths = [rng.randrange(1, 5000) for _ in range(rng.randrange(1, 8))]
        phase, total = 0, 0
        for n in lengths:
            total += output_count(n, phase, ratio)
            phase = next_phase(phase, n, ratio)
        assert total == -(-sum(lengths) // ratio)


def test_counts_at_the_edges():
    assert output_count(0, 0, 4) == 0
    assert output_count(2, 3, 4) == 0, "a song shorter than its phase has no grid point"
    assert output_count(3, 3, 4) == 0
    assert output_count(4, 3, 4) == 1
    assert output_count(8, 0, 4) == 2, "a multiple of the ratio"
    assert output_count(9, 0, 4) == 3
    assert output_count(8, 1, 4) == 2


def test_the_plan_names_its_neighbours_by_version_in_its_material():
    from src.flac_mp4 import StreamInfo
    info = StreamInfo(raw=bytes(34), min_block=4096, max_block=4096, sample_rate=192000, channels=2,
                      bits_per_sample=24, total_samples=1000)
    before = resample.Neighbour("s1", "v1", 100, None, info, 42)
    plan = ResamplePlan(max_rate=48000, source_rate=192000, out_rate=48000, channels=2, bits=24,
                        total_samples=1001, phase=3, before=before)
    assert plan.material() == [resample.RESAMPLE_FORMAT_VERSION, 48000, 48000, 3, resample.CONTEXT_SAMPLES,
                               resample.HEADROOM_DB, ["s1", "v1"], None]
    assert plan.header == "192000-48000" and plan.ratio == 4
    assert plan.samples_out == output_count(1001, 3, 4)
    assert plan.estimated_bytes(4000) == 1000, "a quarter of the rate, the same depth"
    sixteen = ResamplePlan(max_rate=48000, source_rate=192000, out_rate=48000, channels=2, bits=16,
                           total_samples=1001)
    assert sixteen.estimated_bytes(4000) == 1500, "a quarter of the rate, and 16 bits written as 24"


# ---------------------------------------------------------------- helpers for the audio

def music(np, rate: int, n: int, channels: int = 2, seed: int = 1, level: float = 1.0):
    """Something like music, as 24-bit samples: tones to 19.5 kHz, one above 20 kHz that the
    resample removes, filtered noise and a slow swell - continuous, so any join shows."""
    rng = np.random.default_rng(seed)
    t = np.arange(n) / rate
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * 0.29 * t)
    tones = (0.3 * np.sin(2 * np.pi * 440 * t) + 0.12 * np.sin(2 * np.pi * 3150 * t + 1)
             + 0.07 * np.sin(2 * np.pi * 11000 * t) + 0.03 * np.sin(2 * np.pi * 19500 * t)
             + 0.02 * np.sin(2 * np.pi * min(31000, rate / 2 - 5000) * t)) * swell
    noise = rng.standard_normal((n, channels))
    kernel = np.ones(12) / 12
    noise = np.stack([np.convolve(noise[:, c], kernel, "same") for c in range(channels)], 1) * 0.06
    return np.clip(np.rint((tones[:, None] + noise) * FULL * level), BOTTOM, TOP).astype(np.int32)


def write_flac(sf, path: Path, samples, rate: int, bits: int = 24) -> Path:
    """24-bit samples written as a FLAC, the way libsndfile does (fixed 4096-sample blocks)."""
    if bits == 24:
        sf.write(str(path), samples << 8, rate, subtype="PCM_24", format="FLAC")
    else:
        sf.write(str(path), (samples >> 8).astype("int16"), rate, subtype="PCM_16", format="FLAC")
    return path


def metadata(data: bytes):
    """STREAMINFO and where the audio starts, from a whole file."""
    return _read_metadata(data, _skip_id3v2(data))


def tail_of(data: bytes):
    info, _ = metadata(data)
    return resample.tail_samples(info, data[-resample.tail_bytes(info):])


def head_of(data: bytes):
    info, audio = metadata(data)
    end = audio + resample.head_bytes(info)
    return resample.head_samples(info, data[audio:end], whole_file=end >= len(data))


def plan_for(rate: int, out: int, n: int, phase: int = 0, channels: int = 2, bits: int = 24) -> ResamplePlan:
    return ResamplePlan(max_rate=48000, source_rate=rate, out_rate=out, channels=channels, bits=bits,
                        total_samples=n, phase=phase)


def read24(sf, path: Path):
    samples, rate = sf.read(str(path), dtype="int32", always_2d=True)
    return samples >> 8, rate


def floats(np, soxr, samples, rate: int, out: int):
    """One resample of `samples` at once, in float and unrounded, 1.0 being full scale, on a grid
    starting at their first sample. Silence after it, so its length is the grid's, ceil(N / ratio)."""
    ratio = rate // out
    whole = np.concatenate([samples / FULL, np.zeros((ratio, samples.shape[1]))])
    return soxr.resample(whole, rate, out, quality="VHQ")[:-(-len(samples) // ratio)]


def continuous(np, soxr, samples, rate: int, out: int):
    """One resample of the whole album at once, lowered by the headroom and rounded to 24 bits as the
    songs are: what they must join into."""
    return np.rint(floats(np, soxr, samples, rate, out) * FULL * GAIN)


def album(np, sf, tmp_path: Path, rate: int, out: int, lengths: list[int], with_context: bool = True):
    """An album cut from one piece of music at `lengths`, each song resampled on its own - with its
    neighbours' samples read from byte ranges of their files, as the server gets them - and joined."""
    samples = music(np, rate, sum(lengths))
    paths, at = [], 0
    for i, n in enumerate(lengths):
        paths.append(write_flac(sf, tmp_path / f"t{i}.flac", samples[at:at + n], rate))
        at += n
    ratio, phase, outs, counts = rate // out, 0, [], []
    for i, (path, n) in enumerate(zip(paths, lengths)):
        before = tail_of(paths[i - 1].read_bytes()) if with_context and i > 0 else None
        after = head_of(paths[i + 1].read_bytes()) if with_context and i + 1 < len(paths) else None
        made = resample.resample_file(path, tmp_path / f"o{i}.flac", plan=plan_for(rate, out, n, phase),
                                      before=before, after=after)
        got, got_rate = read24(sf, tmp_path / f"o{i}.flac")
        assert got_rate == out and len(got) == made.samples_out == output_count(n, phase, ratio)
        outs.append(got)
        counts.append(len(got))
        phase = next_phase(phase, n, ratio)
    return samples, np.concatenate(outs), counts


# ---------------------------------------------------------------- the joins

@pytest.mark.parametrize("rate, out, cuts", [
    (96000, 48000, (1, 1)),
    (192000, 48000, (1, 3)),
    (384000, 48000, (5, 3)),
    (176400, 44100, (3, 2)),
], ids=["x2", "x4", "x8", "x4 to 44.1"])
def test_songs_resampled_one_at_a_time_join_into_one_resample_of_the_album(tmp_path, rate, out, cuts):
    """
    The whole point: three songs cut from continuous music at splits that aren't multiples of the
    ratio, each resampled on its own with the context of its neighbours, concatenate into exactly
    what one resample of the whole album gives - the same length, and every sample within the one
    LSB of 24-bit rounding (a value within a hair of half an LSB can round the other way).
    """
    np, sf, soxr = libraries()
    lengths = [rate // 2 + cuts[0], rate // 3 + cuts[1], rate // 2]
    samples, joined, _ = album(np, sf, tmp_path, rate, out, lengths)
    reference = continuous(np, soxr, samples, rate, out)

    assert len(joined) == len(reference)
    assert np.abs(joined - reference).max() <= 1


def test_without_context_every_join_clicks(tmp_path):
    """What the context is for: the same album resampled song by song with nothing around each - the
    resampler assumes silence past each end - is off by thousands of LSB at the joins."""
    np, sf, soxr = libraries()
    rate, out = 192000, 48000
    lengths = [rate // 2 + 1, rate // 3 + 3, rate // 2]
    samples, joined, counts = album(np, sf, tmp_path, rate, out, lengths, with_context=False)
    reference = continuous(np, soxr, samples, rate, out)

    join = counts[0]
    assert len(joined) == len(reference), "the grid alone keeps the lengths right"
    assert np.abs(joined[join - 200:join + 200] - reference[join - 200:join + 200]).max() > 10000
    assert np.abs(joined[join + 2000:join + 4000] - reference[join + 2000:join + 4000]).max() <= 1, \
        "away from the joins it is the same resample"


# ---------------------------------------------------------------- what the resample does to the sound

def tone(np, rate: int, frequency: int, seconds: int = 3, level: float = 0.5):
    t = np.arange(rate * seconds) / rate
    wave = np.rint(level * np.sin(2 * np.pi * frequency * t) * FULL).astype(np.int32)
    return np.stack([wave, wave], 1)


def level_at(np, samples, rate: int, frequency: int) -> float:
    """The level of `frequency` in the middle second of `samples`, 1.0 being full scale: a whole
    number of cycles, so nothing leaks from the rest."""
    middle = samples[rate:2 * rate, 0] / FULL
    t = np.arange(rate) / rate
    return 2 * abs(np.sum(middle * np.exp(-2j * np.pi * frequency * t))) / rate


def resampled_tone(np, sf, tmp_path, rate, out, frequency):
    path = write_flac(sf, tmp_path / f"tone{frequency}.flac", tone(np, rate, frequency), rate)
    resample.resample_file(path, tmp_path / f"tone{frequency}.out.flac", plan=plan_for(rate, out, rate * 3))
    got, _ = read24(sf, tmp_path / f"tone{frequency}.out.flac")
    return got


@pytest.mark.parametrize("rate, out", [(192000, 48000), (96000, 48000), (176400, 44100), (352800, 44100)])
@pytest.mark.parametrize("frequency", [1000, 10000, 19000, 20000])
def test_nothing_below_20_khz_changes(tmp_path, rate, out, frequency):
    """Flat within a thousandth of a dB to 20 kHz, 44.1 kHz out included (measured: 3e-8 dB) - every
    frequency lowered by the headroom and by nothing else."""
    np, sf, _ = libraries()
    got = resampled_tone(np, sf, tmp_path, rate, out, frequency)
    change = 20 * math.log10(level_at(np, got, out, frequency) / 0.5)
    assert abs(change + resample.HEADROOM_DB) < 0.001


@pytest.mark.parametrize("frequency, folds_to", [(30000, 18000), (50000, 2000)])
def test_what_is_above_the_new_rates_reach_is_removed_not_folded_down(tmp_path, frequency, folds_to):
    """A tone above 24 kHz leaves nothing where it would alias to - more than 150 dB down."""
    np, sf, _ = libraries()
    got = resampled_tone(np, sf, tmp_path, 192000, 48000, frequency)
    left = level_at(np, got, 48000, folds_to)
    assert left == 0 or 20 * math.log10(left / 0.5) < -150


@pytest.mark.parametrize("channels", [1, 2, 6])
@pytest.mark.parametrize("phase", [0, 3])
def test_the_output_is_a_24_bit_flac_at_the_new_rate_and_the_grids_length(tmp_path, channels, phase):
    np, sf, _ = libraries()
    n = 96000 + 5
    path = write_flac(sf, tmp_path / "in.flac", music(np, 192000, n, channels=channels), 192000, bits=16)
    made = resample.resample_file(path, tmp_path / "out.flac",
                                  plan=plan_for(192000, 48000, n, phase=phase, channels=channels, bits=16))
    info = sf.info(str(tmp_path / "out.flac"))
    assert (info.format, info.subtype, info.samplerate, info.channels) == ("FLAC", "PCM_24", 48000, channels)
    assert info.frames == made.samples_out == output_count(n, phase, 4)
    assert (made.lowered_db, made.beyond_db, made.samples_in) == (resample.HEADROOM_DB, None, n)


@pytest.mark.parametrize("rate, n, phase", [(192000, 1, 1), (192000, 3, 3), (384000, 7, 7), (96000, 1, 1)])
def test_a_song_too_short_to_reach_the_albums_grid_is_refused_not_written_empty(tmp_path, rate, n, phase):
    """A song of a few samples that ends before the album's grid next falls in it has nothing to
    resample to: refused with the reason, and no file written - where it used to write an empty
    one, for the muxer to refuse."""
    np, sf, _ = libraries()
    #? (music() pads anything under its dozen-sample filter out to that)
    path = write_flac(sf, tmp_path / "blip.flac", music(np, rate, 64)[:n], rate)
    with pytest.raises(CannotResample, match="none of them falls on the album's 48 kHz grid"):
        resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(rate, 48000, n, phase=phase))
    assert not (tmp_path / "out.flac").exists()


def test_a_song_one_sample_onto_the_grid_is_one_sample_long(tmp_path):
    np, sf, _ = libraries()
    path = write_flac(sf, tmp_path / "blip.flac", music(np, 192000, 64)[:4], 192000)
    made = resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(192000, 48000, 4, phase=3))
    got, _ = read24(sf, tmp_path / "out.flac")
    assert made.samples_out == len(got) == 1


@pytest.mark.parametrize("rate, out", [(96000, 48000), (192000, 48000), (384000, 48000), (352800, 44100)])
@pytest.mark.parametrize("before", [False, True], ids=["alone", "a song before it"])
def test_a_song_with_no_song_after_it_is_the_grids_length_whatever_its_length(tmp_path, rate, out, before):
    """
    The album's last song, or one whose next song's start couldn't be read: flushed with nothing
    after it, soxr gives round-half-up(N / ratio) samples - one short of the grid's count at 8:1
    when the song runs one or two samples past a grid point, which `ratio` zeros after it make up.
    Every length at every phase comes out the grid's count, with a song before it or none.
    """
    np, sf, _ = libraries()
    ratio = rate // out
    samples = music(np, rate, 1000 * ratio + 2 * ratio)
    pre = music(np, rate, resample.CONTEXT_SAMPLES, seed=3) / FULL if before else None
    for phase in range(ratio):
        for extra in range(ratio):
            n = 1000 * ratio + phase + extra
            path = write_flac(sf, tmp_path / "last.flac", samples[:n], rate)
            made = resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(rate, out, n, phase=phase),
                                          before=pre)
            frames = sf.info(str(tmp_path / "out.flac")).frames
            assert frames == made.samples_out == output_count(n, phase, ratio), f"phase {phase}, N {n}"


# ---------------------------------------------------------------- the headroom, and never clipped

def square(np, rate: int, seconds: float, level: float, frequency: int = 1000):
    t = np.arange(int(rate * seconds)) / rate
    wave = np.sign(np.sin(2 * np.pi * frequency * t + 0.1)) * level
    return np.clip(np.rint(np.stack([wave, -wave], 1) * FULL), BOTTOM, TOP).astype(np.int32)


def loud_master(np, rate: int, n: int):
    """A master of the loudness war: music peak-normalised to -0.1 dBFS, pushed 6 dB into that and
    its peaks cut flat - the kind verify_audio.md measured going 0.79 to 1.73 dB over once resampled."""
    x = music(np, rate, n) / FULL
    top = 10 ** (-0.1 / 20)
    return np.rint(np.clip(x / np.abs(x).max() * top * 2, -top, top) * FULL).astype(np.int32)


def passes(monkeypatch) -> list:
    """The gain of each pass resample_file() makes, as it makes them."""
    gains, real = [], resample._pass

    def counted(source, target, plan, pre, post, gain, stop):
        gains.append(gain)
        return real(source, target, plan, pre, post, gain, stop)

    monkeypatch.setattr(resample, "_pass", counted)
    return gains


def test_every_song_is_lowered_by_the_headroom_and_by_nothing_more(tmp_path, monkeypatch):
    """An ordinary song comes out as exactly one resample of it scaled by the headroom's gain, within
    the one LSB of 24-bit rounding: lowered 3 dB in one pass, and not beyond."""
    np, sf, soxr = libraries()
    n = 96000 + 3
    samples = music(np, 192000, n, level=0.5)
    path = write_flac(sf, tmp_path / "in.flac", samples, 192000)
    gains = passes(monkeypatch)
    made = resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(192000, 48000, n))
    got, _ = read24(sf, tmp_path / "out.flac")

    assert resample.HEADROOM_DB == 3.0
    assert (made.lowered_db, made.beyond_db) == (3.0, None) and made.peak_db < 0
    assert gains == [GAIN]
    assert np.abs(got - np.rint(floats(np, soxr, samples, 192000, 48000) * FULL * GAIN)).max() <= 1


@pytest.mark.parametrize("rate, out, master", [
    (192000, 48000, "loud"), (96000, 48000, "loud"), (176400, 44100, "loud"), (192000, 48000, "square"),
    (192000, 48000, "8.25 kHz square"),
])
def test_a_master_that_goes_over_once_resampled_fits_in_the_headroom(tmp_path, monkeypatch, rate, out, master):
    """
    A hard-clipped loud master goes past full scale once resampled - its lost ultrasonics were
    holding its peaks down - and so does a square wave just under full scale (the measured
    +1.63 dBFS), and an 8.25 kHz one (+2.63, past the 2 dB the headroom first was). By less than the
    headroom: lowered 3 dB like any other song, in one pass, with nothing clipped - so its joins
    with the songs beside it stay exact.
    """
    np, sf, soxr = libraries()
    n = rate // 2
    samples = {"loud": lambda: loud_master(np, rate, n), "square": lambda: square(np, rate, 0.5, 0.999),
               "8.25 kHz square": lambda: square(np, rate, 0.5, 0.999, frequency=8250)}[master]()
    path = write_flac(sf, tmp_path / "over.flac", samples, rate)
    gains = passes(monkeypatch)
    made = resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(rate, out, n))
    got, _ = read24(sf, tmp_path / "out.flac")
    expected = floats(np, soxr, samples, rate, out) * FULL * GAIN

    assert 0.5 < made.peak_db < resample.HEADROOM_DB, "past full scale resampled, within the headroom"
    assert (made.lowered_db, made.beyond_db) == (resample.HEADROOM_DB, None)
    assert gains == [GAIN], "no second pass"
    assert BOTTOM < expected.min() and expected.max() < TOP, "nothing to clip"
    assert np.abs(got - np.rint(expected)).max() <= 1


def overshoot(np, rate: int, seconds: float, level: float = 0.999, signs=(1, -1), out: int = 48000):
    """
    Built to go past full scale once resampled, by more than the headroom: `level` of full scale,
    turned over wherever a band-limited impulse at the new rate's edge is negative, for a hundred
    samples either side of the middle - so the resample, which keeps only what is under that edge,
    adds all of it up at one output sample. Measured at 192 kHz: +7.55 dBFS for `level` 0.999,
    +3.82 for 0.65, on that side only (+0.86 and -2.88 on the other). Each channel is that times its
    sign in `signs`: (1, -1) goes over on both sides, as a square wave does; (-1, -1) at the bottom
    only.
    """
    n = int(rate * seconds)
    ratio = rate // out
    k = np.arange(n) - (n // 2) // ratio * ratio
    wave = np.where(np.sinc(out * 0.95 / rate * k) >= 0, level, -level)
    wave[np.abs(k) > 100] = 0
    return np.rint(np.stack([wave * sign for sign in signs], 1) * FULL).astype(np.int32)


@pytest.mark.parametrize("master", ["both sides", "the bottom only"])
def test_a_song_over_by_more_than_the_headroom_is_lowered_further_by_exactly_enough(tmp_path, monkeypatch,
                                                                                    master):
    """
    A song that would clip even 3 dB down - one built to (overshoot()), since no master measured
    goes that far short of being clipped 18 dB - is resampled a second time, lowered further by
    exactly enough: its loudest sample lands on full scale, and it is exactly one resample of it
    scaled by that gain. And so is a song over on its negative side only, whose top never reaches
    full scale: either side going over is an over.
    """
    np, sf, soxr = libraries()
    n = 96000
    samples = overshoot(np, 192000, 0.5, 0.65, (1, -1) if master == "both sides" else (-1, -1))
    path = write_flac(sf, tmp_path / "over.flac", samples, 192000)
    gains = passes(monkeypatch)
    made = resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(192000, 48000, n))
    got, _ = read24(sf, tmp_path / "out.flac")
    exact = floats(np, soxr, samples, 192000, 48000)
    gain = min(TOP / (exact.max() * FULL), BOTTOM / (exact.min() * FULL))

    assert made.peak_db > resample.HEADROOM_DB, "past full scale even 3 dB down"
    assert made.beyond_db is not None and 0.5 < made.beyond_db < 1
    assert made.lowered_db == resample.HEADROOM_DB + made.beyond_db
    assert abs(made.lowered_db + 20 * math.log10(gain)) < 1e-6, "lowered by exactly enough"
    assert abs(made.lowered_db - made.peak_db) < 0.001, "which is as much as it was over"
    assert len(gains) == 2 and gains[0] == GAIN and abs(gains[1] / gain - 1) < 1e-9
    assert np.abs(got - np.rint(exact * FULL * gain)).max() <= 1
    assert got.max() <= TOP and got.min() >= BOTTOM
    assert got.max() == TOP or got.min() == BOTTOM, "lowered no further than it had to be"
    if master == "the bottom only":
        assert exact.max() * FULL * GAIN < TOP and got.min() == BOTTOM, "over at the bottom, and only there"


def test_the_headroom_is_part_of_what_names_the_file(monkeypatch):
    """A song resampled with another headroom is another file: the headroom is in the plan's
    material, so a change to it never serves a song lowered the old way under the new way's name."""
    plan = plan_for(192000, 48000, 1000)
    before = plan.material()
    monkeypatch.setattr(resample, "HEADROOM_DB", 1.5)
    assert plan.material() != before and 1.5 in plan.material()


# ---------------------------------------------------------------- stopping

class StopAfter(threading.Event):
    """A stop event that sets itself once it has been looked at `times` times - after that many
    blocks, deterministically."""

    def __init__(self, times: int):
        super().__init__()
        self.times = times

    def is_set(self) -> bool:
        self.times -= 1
        if self.times < 0:
            self.set()
        return super().is_set()


def test_a_resample_nobody_waits_for_stops_within_a_block(tmp_path):
    np, sf, _ = libraries()
    n = resample.BLOCK_FRAMES * 6
    path = write_flac(sf, tmp_path / "long.flac", music(np, 192000, n, channels=1), 192000)
    stop = StopAfter(1)
    with pytest.raises(Stopped):
        resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(192000, 48000, n, channels=1), stop=stop)
    assert stop.times == -1, "stopped at the second look: one block read, no more"


class Counted(threading.Event):
    """A stop event that counts how often the resample looks at it, and notes the count when set."""

    def __init__(self):
        super().__init__()
        self.looks, self.set_at = 0, None

    def is_set(self) -> bool:
        self.looks += 1
        return super().is_set()

    def set(self) -> None:
        self.set_at = self.looks
        super().set()


def test_a_stop_set_from_another_thread_is_seen_at_the_next_block(tmp_path):
    """The make's own case: the event is set from the event loop's thread while the resample runs in
    a worker, and it ends at the next block it would have read."""
    np, sf, _ = libraries()
    n = resample.BLOCK_FRAMES * 80
    path = write_flac(sf, tmp_path / "long.flac", music(np, 192000, n, channels=1), 192000)
    stop = Counted()

    def when_it_is_under_way():
        while stop.looks < 3:
            time.sleep(0.0005)
        stop.set()

    threading.Thread(target=when_it_is_under_way, daemon=True).start()
    with pytest.raises(Stopped):
        resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(192000, 48000, n, channels=1), stop=stop)
    #? the next look but one at the latest: the worker may look once between the count being noted
    #? and the event being set
    assert stop.looks - stop.set_at <= 2, "seen within a block"


def test_a_file_that_isnt_what_its_plan_says_is_refused(tmp_path):
    np, sf, _ = libraries()
    path = write_flac(sf, tmp_path / "in.flac", music(np, 96000, 9600), 96000)
    for wrong in (plan_for(192000, 48000, 9600), plan_for(96000, 48000, 9601),
                  plan_for(96000, 48000, 9600, channels=1)):
        with pytest.raises(CannotResample):
            resample.resample_file(path, tmp_path / "out.flac", plan=wrong)


def constant_flac(*, rate: int = 192000, bps: int = 20, channels: int = 2, blocks=(4096,) * 4) -> bytes:
    """
    A FLAC of silence at any depth: each channel of each frame one CONSTANT subframe of 0, so every
    body byte is zero. Valid at 20 and 32 bits, which the muxer tests' encoder, writing samples a byte
    at a time, can't do.
    """
    frames = []
    for number, block in enumerate(blocks):
        header = frame_header(number, block, rate=rate, channels=channels, bps=bps, variable=False,
                              rate_style="table")
        #? per channel a subframe header of 0x00 (constant, no wasted bits) and a value of `bps` zero
        #? bits, the whole padded to a byte
        frame = header + bytes(-(-channels * (8 + bps) // 8))
        frames.append(frame + struct.pack(">H", crc16(frame)))
    sizes = [len(frame) for frame in frames]
    info = struct.pack(">HH", min(blocks), max(blocks)) + min(sizes).to_bytes(3, "big") + max(sizes).to_bytes(3, "big")
    info += ((rate << 44) | ((channels - 1) << 41) | ((bps - 1) << 36) | sum(blocks)).to_bytes(8, "big") + bytes(16)
    return b"fLaC" + bytes((0x80, 0, 0, 34)) + info + b"".join(frames)


@pytest.mark.parametrize("damage", ["one bit", "64 bytes"])
def test_a_flac_damaged_part_way_through_is_refused(tmp_path, damage):
    """A file that opens and then has a frame libFLAC can't decode - down to one bit flipped, which
    its CRC catches - is CannotResample, what the cache refuses and remembers: not a RuntimeError out
    of the read, which it took for a failure worth downloading and resampling again for every
    request."""
    np, sf, _ = libraries()
    n = 192000 * 2
    path = write_flac(sf, tmp_path / "in.flac", music(np, 192000, n), 192000)
    data = bytearray(path.read_bytes())
    middle = len(data) // 2
    if damage == "one bit":
        data[middle] ^= 0x10
    else:
        data[middle:middle + 64] = bytes(b ^ 0xFF for b in data[middle:middle + 64])
    path.write_bytes(bytes(data))
    with pytest.raises(CannotResample, match="couldn't decode all of it"):
        resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(192000, 48000, n))


@pytest.mark.parametrize("bps", [20, 32])
def test_a_flac_libsndfile_cant_open_is_refused(tmp_path, bps):
    """libsndfile 1.2.2 can't open a 20- or 32-bit FLAC - which is why output_rate() never asks it to."""
    libraries()
    path = tmp_path / "deep.flac"
    path.write_bytes(constant_flac(bps=bps))
    with pytest.raises(CannotResample):
        resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(192000, 48000, 4 * 4096, bits=bps))


# ---------------------------------------------------------------- a disk that fills

class ADiskThatFills:
    """The resampled FLAC's file on a disk with `room` bytes free: a write past that is refused the
    way a full disk refuses it, with ENOSPC - or with `code`, for some other trouble."""

    def __init__(self, path: Path, room: int, code: int = errno.ENOSPC):
        self.file = open(path, "wb")
        self.room, self.code = room, code

    def write(self, data: bytes) -> int:
        if self.file.tell() + len(data) > self.room:
            raise OSError(self.code, os.strerror(self.code))
        return self.file.write(data)

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        return self.file.seek(offset, whence)

    def tell(self) -> int:
        return self.file.tell()

    def __enter__(self):
        return self

    def __exit__(self, *exc) -> None:
        self.file.close()


@pytest.mark.parametrize("room", [0, 2000, 60000, "all but a byte"])
def test_a_disk_that_fills_during_the_resample_is_said_to_be_full(tmp_path, monkeypatch, room):
    """
    libsndfile makes a write the disk refuses "System error." in a RuntimeError, which the player's
    cache took for a bug: logged, never tried again. Written through the resample's own file, it is
    the disk's own OSError(ENOSPC) - which the cache clears older songs for and tries once more -
    wherever the disk fills: at the file's first bytes, part-way, or at its very last frame, which
    libsndfile writes as the file closes and says nothing at all about (measured with a file-size
    limit: a FLAC one byte short, and no error).
    """
    np, sf, _ = libraries()
    n = 96000
    path = write_flac(sf, tmp_path / "in.flac", music(np, 192000, n), 192000)
    resample.resample_file(path, tmp_path / "whole.flac", plan=plan_for(192000, 48000, n))
    size = (tmp_path / "whole.flac").stat().st_size
    room = size - 1 if room == "all but a byte" else room
    monkeypatch.setattr(resample, "_open_output", lambda target: ADiskThatFills(target, room))

    with pytest.raises(OSError) as raised:
        resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(192000, 48000, n))
    assert raised.value.errno == errno.ENOSPC
    assert (tmp_path / "out.flac").stat().st_size <= room


def test_any_other_trouble_writing_is_the_oserror_it_is_too(tmp_path, monkeypatch):
    """Not every refused write is a full disk: a broken one is its own OSError, which the cache logs
    and doesn't try again."""
    np, sf, _ = libraries()
    n = 96000
    path = write_flac(sf, tmp_path / "in.flac", music(np, 192000, n), 192000)
    monkeypatch.setattr(resample, "_open_output", lambda target: ADiskThatFills(target, 30000, errno.EIO))
    with pytest.raises(OSError) as raised:
        resample.resample_file(path, tmp_path / "out.flac", plan=plan_for(192000, 48000, n))
    assert raised.value.errno == errno.EIO


def test_written_through_its_own_file_the_flac_is_byte_for_byte_what_libsndfile_writes_to_a_path(tmp_path):
    """What the resample's own file changes is how a failed write is reported, and nothing else."""
    np, sf, _ = libraries()
    samples = music(np, 48000, 100000) << 8
    sf.write(str(tmp_path / "path.flac"), samples, 48000, subtype="PCM_24", format="FLAC")
    with resample._flac_output(tmp_path / "own.flac", 48000, 2) as out:
        for at in range(0, len(samples), 30000):
            out.write(samples[at:at + 30000])
    assert (tmp_path / "own.flac").read_bytes() == (tmp_path / "path.flac").read_bytes()


# ---------------------------------------------------------------- context from part of a file

def a_song(np, sf, tmp_path, rate=192000, n=40000, channels=2, seed=5) -> tuple[bytes, object]:
    path = write_flac(sf, tmp_path / f"song{seed}.flac", music(np, rate, n, channels=channels, seed=seed), rate)
    whole, _ = sf.read(str(path), dtype="float64", always_2d=True)
    return path.read_bytes(), whole


def with_metadata(data: bytes, id3: int = 0, padding: int = 0) -> bytes:
    """The same FLAC with an ID3v2 tag of `id3` bytes in front, and a PADDING block of `padding` bytes
    as its last metadata block."""
    info, audio = metadata(data)
    blocks = bytes((0x00, 0, 0, 34)) + info.raw
    if padding:
        blocks += bytes((0x81,)) + padding.to_bytes(3, "big") + bytes(padding)
    else:
        blocks = bytes((0x80,)) + blocks[1:]
    front = b""
    if id3:
        size = id3 - 10
        front = b"ID3\x04\x00\x00" + bytes(((size >> 21) & 0x7F, (size >> 14) & 0x7F, (size >> 7) & 0x7F,
                                             size & 0x7F)) + bytes(size)
    return front + b"fLaC" + blocks + data[audio:]


def test_the_start_of_a_song_is_read_exactly_from_its_first_frames(tmp_path):
    np, sf, _ = libraries()
    data, whole = a_song(np, sf, tmp_path)
    assert np.array_equal(head_of(data), whole[:resample.CONTEXT_SAMPLES])


def test_the_start_is_found_behind_an_id3_tag_and_a_big_metadata_block(tmp_path):
    """Where the audio starts is walked to through the metadata, however much of it there is - a
    cover can be megabytes - and an ID3v2 tag some taggers put in front."""
    np, sf, _ = libraries()
    data, whole = a_song(np, sf, tmp_path)
    tagged = with_metadata(data, id3=2048, padding=100_000)
    info, audio = metadata(tagged)
    assert audio > 100_000
    got = resample.head_samples(info, tagged[audio:audio + resample.head_bytes(info)])
    assert np.array_equal(got, whole[:resample.CONTEXT_SAMPLES])


def test_the_end_of_a_song_is_read_exactly_from_its_last_bytes(tmp_path):
    np, sf, _ = libraries()
    data, whole = a_song(np, sf, tmp_path)
    assert np.array_equal(tail_of(data), whole[-resample.CONTEXT_SAMPLES:])


def ape_tag(items: bytes, header: bool = False) -> bytes:
    """An APEv2 tag: its items and the footer - and with `header`, a header in front of them, which
    the size in the footer doesn't count (flag bit 31: the tag has one; bit 29: this is it)."""
    size, flags = len(items) + 32, (0x80000000 if header else 0)
    front = b"APETAGEX" + struct.pack("<IIII8x", 2000, size, 1, flags | 0x20000000) if header else b""
    return front + items + b"APETAGEX" + struct.pack("<IIII8x", 2000, size, 1, flags)


@pytest.mark.parametrize("trailer", [b"TAG" + bytes(125), ape_tag(b"x" * 300), ape_tag(b"y" * 50) + b"TAG" + bytes(125),
                                     ape_tag(b"z" * 300, header=True)],
                         ids=["id3v1", "apev2", "both", "apev2 with a header"])
def test_the_end_is_found_before_a_tag_appended_to_the_file(tmp_path, trailer):
    np, sf, _ = libraries()
    data, whole = a_song(np, sf, tmp_path)
    info, _ = metadata(data)
    tagged = data + trailer
    assert resample.trailer_length(tagged) == len(trailer)
    got = resample.tail_samples(info, tagged[-(resample.tail_bytes(info) + len(trailer)):])
    assert np.array_equal(got, whole[-resample.CONTEXT_SAMPLES:])


def test_a_song_shorter_than_the_context_is_all_there_is(tmp_path):
    np, sf, _ = libraries()
    data, whole = a_song(np, sf, tmp_path, n=3001)
    info, audio = metadata(data)
    assert np.array_equal(resample.tail_samples(info, data[audio:]), whole)
    assert np.array_equal(resample.head_samples(info, data[audio:], whole_file=True), whole)


def test_too_few_bytes_are_refused_never_read_wrong(tmp_path):
    """Short of the frames wanted is a refusal - the join goes without context - never samples from
    the wrong place."""
    np, sf, _ = libraries()
    data, whole = a_song(np, sf, tmp_path, n=120000)
    info, audio = metadata(data)
    for cut in range(2000, 60000, 7919):
        for got in (lambda: resample.tail_samples(info, data[-cut:]),
                    lambda: resample.head_samples(info, data[audio:audio + cut])):
            try:
                samples = got()
            except CannotResample:
                continue
            n = len(samples)
            assert np.array_equal(samples, whole[-n:]) or np.array_equal(samples, whole[:n])


def test_bytes_that_dont_start_or_end_where_the_song_does_are_refused(tmp_path):
    """A head read from anywhere but the song's first frame, a tail that stops short of its last, and
    a tail holding fewer samples than wanted from partway through: each refused, never read as the
    song's own start or end - the first two would lend samples from the middle of the song."""
    np, sf, _ = libraries()
    data, _ = a_song(np, sf, tmp_path)
    info, audio = metadata(data)
    frames = resample.whole_frames(data[audio:], 0, info, at_end=True)
    for start in (audio + frames[1].start, audio + 1):
        with pytest.raises(CannotResample):
            resample.head_samples(info, data[start:start + resample.head_bytes(info)])
    end = audio + frames[-3].end
    with pytest.raises(CannotResample, match="STREAMINFO says"):
        resample.tail_samples(info, data[end - resample.tail_bytes(info):end])
    with pytest.raises(CannotResample, match="samples of the"):
        resample.tail_samples(info, data[audio + frames[-2].start:])


def test_a_variable_block_stream_is_read_exactly_or_refused():
    np, sf, _ = libraries()
    data, _ = encode(rate=192000, bps=24, variable=True, blocks=(4096, 1152, 4096, 576, 4608, 4096, 2048, 1000),
                     seed=11)
    whole, _ = sf.read(io.BytesIO(data), dtype="float64", always_2d=True)
    info, audio = metadata(data)
    for n in (1000, 5000, 20000):
        for got, expected in ((lambda: resample.tail_samples(info, data[audio:], n), whole[-n:]),
                              (lambda: resample.head_samples(info, data[audio:], n, whole_file=True), whole[:n])):
            try:
                samples = got()
            except CannotResample:
                continue
            assert np.array_equal(samples, expected)


def test_a_false_header_inside_the_audio_never_reads_the_wrong_samples():
    """A copy of the next frame's header planted in a frame's samples, right where a tail read
    starts: the frames found are the real ones, or none."""
    np, sf, _ = libraries()
    blocks = (4096,) * 10 + (1000,)
    data, frames = encode(rate=192000, bps=24, blocks=blocks, seed=21, plant={6: (100, lambda headers: headers[7])})
    whole, _ = sf.read(io.BytesIO(data), dtype="float64", always_2d=True)
    info, _ = metadata(data)
    real = frames[7][1][:6]
    planted = data.find(real, frames[6][0] + 6)
    assert frames[6][0] < planted < frames[7][0], "the copy is inside frame 6"
    for start in (planted - 1, planted, frames[6][0] + 50):
        try:
            samples = resample.tail_samples(info, data[start:], 8000)
        except CannotResample:
            continue
        assert np.array_equal(samples, whole[-8000:])


def test_a_stream_built_to_be_checksummed_over_and_over_is_refused():
    """A frame full of copies of the next header, each one checked against every later copy, would
    hold a worker thread for as long as its author liked; the checksumming is bounded."""
    libraries()
    blocks = (4096,) * 3 + (1000,)
    header = frame_header(1, 4096, rate=192000, channels=2, bps=24, variable=False, rate_style="table")
    data, _ = encode(rate=192000, bps=24, blocks=blocks, seed=4, plant={0: (0, header * (4096 * 3 // len(header)))})
    info, audio = metadata(data)
    began = time.monotonic()
    with pytest.raises(CannotResample, match="checksumming"):
        resample.head_samples(info, data[audio:], 5000, whole_file=True)
    assert time.monotonic() - began < 1


def packed_with_headers(max_frame: int, number: int = 5):
    """A STREAMINFO claiming frames up to `max_frame` bytes, and a valid frame header carrying
    `number` - what a stretch of a crafted file is packed with, header after header, none of them
    ever followed by the next number: nothing chains, and each one is a start to try."""
    from src.flac_mp4 import _crc8, _parse_streaminfo
    raw = struct.pack(">HH", 4096, 4096) + (0).to_bytes(3, "big") + max_frame.to_bytes(3, "big")
    raw += ((192000 << 44) | (1 << 41) | (23 << 36) | 10_000_000).to_bytes(8, "big") + bytes(16)
    header = bytes((0xFF, 0xF8, (12 << 4) | 3, (1 << 4) | (6 << 1), number))
    return _parse_streaminfo(raw), header + bytes((_crc8(header),))


@pytest.mark.parametrize("max_frame", [16000, 1_390_000])
def test_a_context_packed_with_headers_that_never_chain_is_refused_at_once(max_frame):
    """
    A Soulseek peer's file whose tail or head is nothing but valid frame headers, numbered so no two
    ever chain: every one is a start to try, and each try looked at every header within a frame's
    reach - measured at 25 s for a frame reach of 16 KB, and days at what CONTEXT_READ_MAX lets
    through, in a worker thread no timeout stops. The sync codes that start nothing are counted and
    bounded, as the muxer bounds them: refused, in a moment, whatever the reach.
    """
    libraries()
    info, header = packed_with_headers(max_frame)
    tail = header * (resample.tail_bytes(info) // len(header))
    head = packed_with_headers(max_frame, 0)[1] + header * (resample.head_bytes(info) // len(header))
    for read in (lambda: resample.tail_samples(info, tail), lambda: resample.head_samples(info, head)):
        began = time.monotonic()
        with pytest.raises(CannotResample, match="sync codes that start no frame"):
            read()
        assert time.monotonic() - began < 1


# ---------------------------------------------------------------- the libraries

def test_what_is_missing_is_said(monkeypatch):
    monkeypatch.setattr(resample, "LIBRARIES", ("json", "no_such_audio_library", "another_one_gone"))
    resample._missing.cache_clear()
    try:
        assert resample.missing_libraries() == "no_such_audio_library, another_one_gone"
    finally:
        resample._missing.cache_clear()


def test_the_audio_libraries_are_there_in_ci():
    """
    Every audio test here is skipped without numpy, soxr and soundfile, which is right on a laptop
    running from source and wrong in CI, where requirements.txt installs them: a CI run where they
    didn't install would pass having tested none of this. GitHub Actions sets CI=true.
    """
    missing = resample.missing_libraries()
    if missing and not os.environ.get("CI"):
        pytest.skip(f"{missing} isn't installed here; CI must have it")
    assert missing is None, f"{missing} couldn't be imported - every resample test was skipped"
