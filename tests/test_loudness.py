"""
How loud a song is, and the gain that levels it (src/loudness.py) - the player's Normalization
(2.0.0-player.62): the K-weighting by FFT against the IIR it stands for, EBU Tech 3341's test cases,
the histogram against the exact block computation, an album's pooled loudness, mono as dual mono,
silence, the gain rule and its bound, the streamed measure, and what is kept.

The audio tests need numpy and soundfile (and soxr for a hi-res song's decimated loudness), and skip
without them - except in CI, where test_resample.py's last test fails instead. Every FLAC is written
here with soundfile: no binary files.
"""

import io
import math
import os
import struct
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import levels, loudness  # noqa: E402
from src.loudness import (BINS, FULL_DB, REFERENCE_LUFS, CannotMeasure, Measurement, audio_key,  # noqa: E402
                          gain_for, loudness_of, measure_file, pack, unpack)
from test_resample import constant_flac  # noqa: E402

FULL = float(1 << 23)
TOP, BOTTOM = (1 << 23) - 1, -(1 << 23)


def audio():
    """numpy and soundfile - or this test is skipped (test_resample.py's last test fails in CI instead)."""
    return pytest.importorskip("numpy"), pytest.importorskip("soundfile")


def tone(np, db: float, seconds: float, rate: int, frequency: float = 1000.0, channels: int = 2):
    """A sine at `db` dBFS, as EBU Tech 3341 builds its cases: the same in every channel."""
    t = np.arange(int(round(seconds * rate))) / rate
    wave = 10 ** (db / 20) * np.sin(2 * np.pi * frequency * t)
    return np.stack([wave] * channels, 1)


def metered(np, samples, rate: int) -> Measurement:
    """`samples` through the measure's own meter, whole, as one song."""
    meter = loudness._Meter(np, rate, samples.shape[1])
    meter.push(np.ascontiguousarray(samples, dtype=np.float32))
    meter.finish()
    return Measurement(peak=float(np.max(np.abs(samples))), histogram=meter.histogram(), blocks=meter.blocks,
                       seconds=len(samples) / rate)


def exact(np, samples, rate: int) -> float:
    """BS.1770's integrated loudness worked out exactly, block by block - no histogram: the blocks from a
    running sum of the K-weighted signal, the gates on the blocks themselves. What the histogram's 0.1 LU
    bins stand for (the K-weighting itself is held to its biquads above)."""
    weighted = loudness.kfilter(np, samples, rate).astype(np.float64)
    weight = 2.0 if samples.shape[1] == 1 else 1.0
    hop = round(rate * 0.1)
    squares = np.concatenate([[0.0], np.cumsum(np.sum(weighted * weighted, axis=1))])
    starts = np.arange(0, len(weighted) - 4 * hop + 1, hop)
    powers = (squares[starts + 4 * hop] - squares[starts]) / (4 * hop) * weight
    lufs = -0.691 + 10 * np.log10(np.maximum(powers, 1e-300))
    kept = powers[lufs >= -70]
    if not len(kept):
        return -math.inf
    gate = -0.691 + 10 * np.log10(np.mean(kept)) - 10
    kept = kept[-0.691 + 10 * np.log10(kept) >= gate]
    return float(-0.691 + 10 * np.log10(np.mean(kept)))


def flac(np, sf, path: Path, samples, rate: int, bits: int = 24) -> Path:
    """Float samples written as a FLAC of that depth."""
    if bits == 24:
        sf.write(str(path), (np.clip(np.rint(samples * FULL), BOTTOM, TOP).astype(np.int32) << 8), rate,
                 subtype="PCM_24", format="FLAC")
    else:
        sf.write(str(path), np.clip(np.rint(samples * 32768), -32768, 32767).astype(np.int16), rate,
                 subtype="PCM_16", format="FLAC")
    return path


# ---------------------------------------------------------------- the K-weighting

@pytest.mark.parametrize("rate", [44100, 48000, 96000])
def test_the_k_weighting_by_fft_is_the_iir_it_stands_for(rate):
    """
    Five seconds of noise K-weighted by the FFT overlap-add, against the two biquads run sample by
    sample (libebur128's filter): the difference is the impulse response's cut tail - its last
    -120 dB of energy, a millionth of the signal - and float32's rounding, and nothing else.
    """
    np, _ = audio()
    noise = np.random.default_rng(rate).standard_normal((5 * rate, 2)) * 0.3
    (b1, a1), (b2, a2) = loudness.k_coeffs(rate)
    for channel in range(2):
        iir = np.array(loudness.biquad(loudness.biquad(noise[:, channel].tolist(), b1, a1), b2, a2))
        fft = loudness.kfilter(np, noise, rate)[:, channel].astype(np.float64)
        residual = math.sqrt(np.mean((fft - iir) ** 2) / np.mean(iir ** 2))
        assert residual < 2 * 10 ** (loudness.TAIL_DB / 20), residual


@pytest.mark.parametrize("rate, taps", [(44100, 2362), (48000, 2561)])
def test_the_impulse_is_cut_where_the_rest_of_its_energy_is_under_120_db(rate, taps):
    response = loudness.k_impulse(rate)
    assert len(response) == taps
    assert 0.050 <= len(response) / rate <= 0.054


def test_the_fft_streamed_in_any_pieces_is_the_same_bytes():
    """The overlap-add cuts the input at its own segments however it arrives: fed a sample at a time or
    in one go, the same float32 bytes."""
    np, _ = audio()
    noise = np.random.default_rng(3).standard_normal((200_000, 2)).astype(np.float32) * 0.3
    whole = loudness.kfilter(np, noise, 44100)
    run = loudness._OverlapAdd(np, loudness.k_impulse(44100), 2)
    pieces, at = [], 0
    for size in [1, 4095, 7, 65536, 3, 100_000, 10_000]:
        pieces += run.push(noise[at:at + size])
        at += size
    pieces += run.push(noise[at:]) + run.finish()
    assert np.concatenate(pieces).tobytes() == whole.tobytes()


# ---------------------------------------------------------------- EBU Tech 3341

def tech3341(np, rate: int) -> dict[str, tuple]:
    """EBU Tech 3341's cases 1-5 (its 1 kHz stereo tones) and what each must read, LUFS."""
    def t(db, seconds):
        return tone(np, db, seconds, rate)
    return {
        "1": (t(-23, 20), -23.0),
        "2": (t(-33, 20), -33.0),
        "3": (np.concatenate([t(-36, 10), t(-23, 60), t(-36, 10)]), -23.0),
        "4": (np.concatenate([t(-72, 10), t(-36, 10), t(-23, 60), t(-36, 10), t(-72, 10)]), -23.0),
        "5": (np.concatenate([t(-26, 20), t(-20, 20.1), t(-26, 20)]), -23.0),
    }


@pytest.mark.parametrize("rate", [44100, 48000, 96000, 192000])
def test_ebu_tech_3341_cases_1_to_5_are_within_its_tenth_of_a_lu(rate):
    np, _ = audio()
    for case, (samples, wanted) in tech3341(np, rate).items():
        assert abs(metered(np, samples, rate).loudness - wanted) <= 0.1, (rate, case)


@pytest.mark.parametrize("rate", [96000, 192000])
def test_a_hi_res_files_loudness_is_measured_decimated_and_still_right(tmp_path, monkeypatch, rate):
    """Above 48 kHz measure_file measures the loudness at 48 kHz (soxr HQ) - its meter runs at 48 kHz, not
    the song's own rate: EBU 3341's cases 1 and 5 from a 24-bit FLAC at the song's own rate still read
    within 0.1 LU, and the peak is the file's own."""
    np, sf = audio()
    pytest.importorskip("soxr")
    rates = []
    real = loudness._Meter

    class Spy(real):
        def __init__(self, np, rate, channels):
            rates.append(rate)
            super().__init__(np, rate, channels)

    monkeypatch.setattr(loudness, "_Meter", Spy)
    for case in ("1", "5"):
        samples, wanted = tech3341(np, rate)[case]
        path = flac(np, sf, tmp_path / f"{case}.flac", samples, rate)
        measured = measure_file(path)
        assert abs(measured.loudness - wanted) <= 0.1, case
        own, _ = sf.read(str(path), dtype="float32", always_2d=True)
        assert measured.peak == float(np.max(np.abs(own)))
    assert rates == [48000, 48000], "measured decimated to 48 kHz"


# ---------------------------------------------------------------- the histogram

def swelling(np, rng, rate: int, seconds: float):
    """Something like a stretch of music: noise and a tone under a slow swell of random depth, at a random
    level - its blocks spread over many bins, as a song's are."""
    t = np.arange(int(seconds * rate)) / rate
    swell = 10 ** ((rng.uniform(-30, -6) + rng.uniform(3, 12) * np.sin(2 * np.pi * rng.uniform(0.02, 0.2) * t)) / 20)
    noise = rng.standard_normal((len(t), 2)) * 0.3 * swell[:, None]
    return noise + (0.5 * np.sin(2 * np.pi * rng.uniform(100, 5000) * t) * swell)[:, None]


def test_the_histogram_is_within_005_lu_of_the_exact_block_computation():
    """
    Twenty random stretches of something like music, measured through the histogram, against the exact
    computation on the blocks themselves: a block's energy is its 0.1 LU bin's centre, and the relative
    gate is worked out from those centres - libebur128's histogram mode. Measured, 0.034 LU at the most
    over these twenty. (A few seconds of a tone exactly at the relative gate can flip a run of blocks
    in or out - 0.2 LU on a handful of blocks; no song is that.)
    """
    np, _ = audio()
    rng = np.random.default_rng(62)
    rate = 44100
    for n in range(20):
        samples = swelling(np, rng, rate, float(rng.uniform(20, 40)))
        assert abs(metered(np, samples, rate).loudness - exact(np, samples, rate)) <= 0.05, n


def test_an_albums_loudness_is_its_songs_blocks_pooled():
    """
    An album's loudness is its songs' histograms added up, bin by bin - exactly the loudness of all
    their blocks together, with no second decode. Against the whole album measured as one file: the
    blocks that would straddle a join (three a join) and the filter's start in each song are all that
    differ - within 0.05 LU, cut on 100 ms boundaries or not.
    """
    np, _ = audio()
    rate = 48000
    rng = np.random.default_rng(7)
    whole = np.concatenate([swelling(np, rng, rate, 40), swelling(np, rng, rate, 35), swelling(np, rng, rate, 45)])
    for cuts in ([rate * 40, rate * 75], [rate * 40 + 1001, rate * 75 - 333]):
        songs = np.split(whole, cuts)
        measured = [metered(np, song, rate) for song in songs]
        pooled = loudness.pooled(measured)
        assert pooled == [sum(dict(m.histogram).get(i, 0) for m in measured) for i in range(BINS)]
        assert sum(pooled) == sum(m.blocks for m in measured) - sum(  # every block counted, bar the gated
            m.blocks - sum(count for _, count in m.histogram) for m in measured)
        assert abs(loudness_of(measured) - metered(np, whole, rate).loudness) <= 0.05
        assert loudness_of(measured) == loudness_of([Measurement(1.0, tuple(
            (i, c) for i, c in enumerate(pooled) if c), sum(pooled), 0.0)])


def test_mono_is_counted_as_dual_mono():
    """A mono file is heard in both ears: it measures as the same signal in both channels of a stereo
    file, and 3.01 dB louder than that signal in one channel alone."""
    np, _ = audio()
    rate = 44100
    noise = np.random.default_rng(5).standard_normal((rate * 5, 1)) * 0.2
    mono = metered(np, noise, rate).loudness
    both = metered(np, np.concatenate([noise, noise], 1), rate).loudness
    left = metered(np, np.concatenate([noise, np.zeros_like(noise)], 1), rate).loudness
    assert abs(mono - both) < 1e-9
    assert abs(mono - left - 10 * math.log10(2)) <= 0.1


def test_silence_has_no_loudness_and_asks_for_no_gain():
    np, _ = audio()
    quiet = metered(np, np.zeros((44100 * 3, 2)), 44100)
    assert quiet.loudness == -math.inf and quiet.histogram == ()
    gain = gain_for(quiet.loudness, quiet.peak)
    assert (gain.gain_db, gain.wanted_db, gain.held) == (0.0, 0.0, False)
    #? under the absolute gate is silence too: -80 dBFS
    assert metered(np, tone(np, -80, 3, 44100), 44100).loudness == -math.inf


# ---------------------------------------------------------------- the gain

def test_the_gain_takes_a_song_to_the_reference():
    gain = gain_for(-10.6, 10 ** (-1 / 20))
    assert gain.wanted_db == pytest.approx(REFERENCE_LUFS + 10.6)
    assert gain.gain_db == -7.4 and not gain.held


def test_the_gain_is_held_under_the_peak():
    """A quiet song brought up stops where its loudest sample reaches the largest 24-bit sample."""
    gain = gain_for(-24.0, 10 ** (-3.5 / 20))
    assert gain.wanted_db == pytest.approx(6.0)
    assert gain.held and gain.gain_db == math.floor((FULL_DB + 3.5) * 100) / 100
    assert gain.gain_db < 3.5


def test_the_resamples_room_is_reserved_inside_the_limit():
    unheld = gain_for(-20.0, 10 ** (-6 / 20))
    assert unheld.gain_db == 2.0 and not unheld.held
    assert gain_for(-20.0, 10 ** (-6 / 20), reserve_db=3.0).gain_db == 2.0, "room enough for both"
    reserved = gain_for(-20.0, 10 ** (-4 / 20), reserve_db=3.0)
    assert reserved.held and reserved.gain_db == math.floor((FULL_DB + 4 - 3) * 100) / 100 == 0.99


@pytest.mark.parametrize("wanted", [-7.42, -7.425, -7.4299999, 1.2, 0.0, -0.001, 3.999])
def test_the_gain_is_rounded_down_to_the_hundredth(wanted):
    gain = gain_for(REFERENCE_LUFS - wanted, 0.01)
    assert gain.gain_db == math.floor(round(wanted * 100, 6)) / 100
    assert gain.gain_db <= wanted + 1e-9
    assert f"{gain.gain_db:+.2f}" == f"{math.floor(round(wanted * 100, 6)) / 100:+.2f}"


def test_no_input_can_take_a_sample_past_24_bits_after_the_rule():
    """Every peak a 24-bit or 16-bit sample can have, every loudness and reserve: the peak quantised at
    the gain the rule gives stays inside 24 bits, either sign."""
    np, _ = audio()
    rng = np.random.default_rng(23)
    peaks = list(rng.integers(1, 1 << 23, 3000)) + [1, (1 << 23) - 1, 1 << 23] + [k << 8 for k in rng.integers(1, 1 << 15, 500)]
    for peak in peaks:
        value = int(peak) / FULL
        for lufs in (-60.0, -30.0, -18.0, -5.0):
            for reserve in (0.0, 3.0):
                gain = gain_for(lufs, value, reserve)
                scale = FULL * 10 ** (gain.gain_db / 20)
                for sign in (1, -1):
                    q = float(np.rint(np.float64(sign * value) * scale))
                    assert BOTTOM <= q <= TOP, (peak, lufs, reserve, gain)
                    if sign == 1:
                        assert q <= TOP


# ---------------------------------------------------------------- measuring a file

def test_measure_file_streamed_in_any_blocks_is_one_measurement(tmp_path):
    """Read 4096 samples at a time or all at once, the same histogram, peak and count - the overlap-add
    and the partial 100 ms segment carried across blocks."""
    np, sf = audio()
    rng = np.random.default_rng(11)
    samples = np.concatenate([rng.standard_normal((44100 * 4 + 777, 2)) * 0.15, tone(np, -9, 3.3, 44100)])
    path = flac(np, sf, tmp_path / "song.flac", samples, 44100, bits=16)
    small = measure_file(path, block_frames=4096)
    big = measure_file(path, block_frames=1 << 22)
    assert small == big
    assert small.seconds == pytest.approx(len(samples) / 44100)
    own, _ = sf.read(str(path), dtype="float32", always_2d=True)
    assert abs(small.loudness - metered(np, own, 44100).loudness) < 1e-9


def test_a_stop_ends_a_measurement_within_a_block(tmp_path):
    np, sf = audio()
    path = flac(np, sf, tmp_path / "song.flac", tone(np, -20, 3, 44100), 44100)

    class After(Exception):
        pass

    class StopSoon:
        def __init__(self):
            self.looks = 0

        def is_set(self):
            self.looks += 1
            return self.looks > 2

    stop = StopSoon()
    with pytest.raises(loudness.Stopped):
        measure_file(path, stop=stop, block_frames=4096)
    assert stop.looks == 3


@pytest.mark.parametrize("bps", [20, 32])
def test_a_flac_libsndfile_cant_open_cant_be_measured(tmp_path, bps):
    audio()
    path = tmp_path / "song.flac"
    path.write_bytes(constant_flac(bps=bps))
    with pytest.raises(CannotMeasure):
        measure_file(path)


def test_only_flac_and_only_mono_or_stereo_is_measured(tmp_path):
    np, sf = audio()
    wav = tmp_path / "song.wav"
    sf.write(str(wav), tone(np, -20, 1, 44100), 44100, subtype="PCM_16", format="WAV")
    with pytest.raises(CannotMeasure, match="not FLAC"):
        measure_file(wav)
    surround = tmp_path / "surround.flac"
    sf.write(str(surround), tone(np, -20, 1, 44100, channels=6), 44100, subtype="PCM_16", format="FLAC")
    with pytest.raises(CannotMeasure, match="6 channels"):
        measure_file(surround)


# ---------------------------------------------------------------- what is kept

def test_a_histogram_is_kept_as_little_endian_pairs_and_read_back():
    histogram = ((0, 1), (470, 123456), (999, 7))
    blob = pack(histogram)
    assert blob == struct.pack("<HIHIHI", 0, 1, 470, 123456, 999, 7)
    assert unpack(blob) == histogram
    assert unpack(b"") == ()


@pytest.mark.parametrize("blob", [b"\x00", struct.pack("<HIHI", 5, 1, 4, 1), struct.pack("<HI", 1000, 1),
                                  struct.pack("<HI", 3, 0), struct.pack("<HIHI", 3, 1, 3, 1)])
def test_a_histogram_that_isnt_one_is_refused(blob):
    with pytest.raises(ValueError):
        unpack(blob)


def test_a_song_is_kept_by_its_audio_not_its_file():
    """STREAMINFO's 34 bytes hold the audio's MD5: a retag leaves them alone. A zero MD5 is kept by the
    file's version - and with none to go by, not at all."""
    info = bytes(range(34))
    import hashlib
    assert audio_key(info, "v1") == "s:" + hashlib.sha256(info).hexdigest() == audio_key(info, "v2")
    zeros = info[:18] + bytes(16)
    assert audio_key(zeros, "abc") == "v:abc"
    assert audio_key(zeros, None) is None
    assert audio_key(b"short", "v") is None


def test_a_filed_flacs_streaminfo_is_read_from_its_head(tmp_path):
    """Part B reads the key from the file itself - the same 34 bytes Navidrome's copy carries."""
    np, sf = audio()
    path = flac(np, sf, tmp_path / "song.flac", tone(np, -20, 1, 44100), 44100)
    data = path.read_bytes()
    assert levels.streaminfo_of(path) == data[8:42]
    tagged = tmp_path / "tagged.flac"
    tag = b"ID3\x04\x00\x00\x00\x00\x00\x0a" + bytes(10)
    tagged.write_bytes(tag + data)
    assert levels.streaminfo_of(tagged) == data[8:42]
    (tmp_path / "not.flac").write_bytes(b"RIFF" + bytes(100))
    assert levels.streaminfo_of(tmp_path / "not.flac") is None
    assert levels.streaminfo_of(tmp_path / "missing.flac") is None


def test_the_libraries_a_level_needs_are_there_in_ci():
    """As test_resample.py's: every audio test here skips without numpy and soundfile, which CI has."""
    missing = levels.missing_libraries()
    if missing and not os.environ.get("CI"):
        pytest.skip(f"{missing} isn't installed here; CI must have it")
    assert missing is None


def test_a_measurement_round_trips_through_a_row():
    measurement = Measurement(peak=0.5, histogram=((400, 3), (401, 9)), blocks=14, seconds=1.7)
    row = levels._row("s:abc", measurement)
    assert levels._measurement(row) == measurement
    assert levels._measurement({**row, "algorithm": loudness.ALGORITHM_VERSION + 1}) is None
    assert levels._measurement({**row, "histogram": b"\x01"}) is None
    assert isinstance(io.BytesIO(row["histogram"]).read(), bytes)
