"""
How loud a song is, and the gain that levels it - the player's Normalization (2.0.0-player.62).

James: "I'd like the default to be album-wide normalization when an album is played, but when any
single song is played, it should be song normalization." deadwax applies the gain itself, in the copy
it already makes of a FLAC song for the player (src/resample.py, src/player_cache.py): an iPhone locks
the audio element's volume, and Web Audio on the playing element is banned (it breaks locked playback).

ONE RULER. deadwax measures every song itself and ignores ReplayGain tags: Soulseek files come tagged
every which way (ReplayGain 1's 89 dB model, ReplayGain 2.0, R128 tags, nothing), and a tag can be
stale. One measurement, one reference, one algorithm levels every album against every other. Nothing
is written into the music files; the measurements live in deadwax's database (store.py's `loudness`),
keyed by each FLAC's STREAMINFO (audio_key()), so a retag, a rename or a re-file keeps them.

THE MEASUREMENT is ITU-R BS.1770-4's integrated loudness with EBU R128's gating, as ReplayGain 2.0
uses it:
  - K-weighting re-derived for the song's rate, as libebur128 does (k_coeffs()). numpy has no IIR
    filter and scipy isn't in the image, so the two biquads are run once over an impulse in plain
    Python (k_impulse(), a quarter of a second, milliseconds) and the filter is applied as an FFT
    overlap-add of that impulse response, truncated where the rest of its energy is under -120 dB
    (about 52 ms at any rate), in float32 (_OverlapAdd).
  - 400 ms blocks every 100 ms - each block the mean of four 100 ms segments' sums of squares, which
    is what lets the measure stream - channels summed with weight 1, and MONO COUNTED AS DUAL MONO
    (x2, +3.01 dB: on headphones a mono file is heard in both ears); absolute gate -70 LUFS, relative
    gate -10 LU.
  - Kept per song as a HISTOGRAM of block loudness - 1000 bins of 0.1 LU from -70 to +30 LUFS, counts
    only, each bin's energy that of its centre, the relative gate taking the bins whose centre is at or
    above it: libebur128's histogram mode. A song's loudness is its histogram's; an ALBUM's is its
    songs' histograms pooled (loudness_of()), so album gain needs no second decode, and a song measured
    once is never decoded again.
  - Above 48 kHz the LOUDNESS is measured after decimating by the song's whole ratio (soxr HQ, to 44.1
    or 48 kHz - measured -24.787 LUFS at 96 and 192 kHz against -24.808/-24.819 native, and 1.9 s
    instead of 4.4 for a 4-minute 24/192 song). The PEAK is always the native samples'.
  - STREAMED: measure_file() reads a block at a time, carries the overlap-add's tail and the partial
    100 ms segment across blocks, and never holds a song whole; a stop event is looked at once a block.
  - Checked against EBU Tech 3341's cases 1-5 (within its +-0.1 LU) at 44.1, 48, 96 and 192 kHz -
    tests/test_loudness.py - and against ffmpeg's ebur128 within 0.07 LU (the design's prototype).

THE GAIN (gain_for()): REFERENCE_LUFS - the loudness, held under the song's (or the album's) sample
peak so nothing clips - with HEADROOM_DB more room when the copy is also resampled, for the resample's
own ringing - and rounded DOWN to 0.01 dB, the value the copy's cache key carries and its bytes are
made from.

Pure but for measure_file(), which reads a file. numpy, soundfile and soxr are imported inside it,
never at the top: a deadwax without them starts as ever and levels nothing.
"""

import hashlib
import math
import struct
from dataclasses import dataclass
from functools import cache

#? Stored with each measurement (store.py's `loudness.algorithm`): a row of another version is measured
#? again. Bump it whenever what a measurement holds changes - the filter, the gating, the bins.
ALGORITHM_VERSION = 1

#? ReplayGain 2.0's reference loudness: every song (or album) is brought to this.
REFERENCE_LUFS = -18.0

#? The largest 24-bit sample, in dBFS: a gain that takes a song's peak to this can't pass it, even
#? rounded (gain_for()).
FULL_DB = 20 * math.log10(((1 << 23) - 1) / (1 << 23))

#? The histogram: BINS bins of BIN_LU from FLOOR_LUFS - libebur128's histogram mode.
BINS = 1000
BIN_LU = 0.1
FLOOR_LUFS = -70.0
#? The relative gate, in LU under the absolutely gated loudness.
RELATIVE_GATE_LU = -10.0
#? BS.1770's constant in "-0.691 + 10 log10(mean square)".
OFFSET = -0.691

#? What can be measured: 1 or 2 channels (stereo, or mono counted as dual mono), at the depths
#? libsndfile 1.2.2 opens (it can't open a 20- or 32-bit FLAC at all, measured).
MEASURED_CHANNELS = frozenset({1, 2})
MEASURED_DEPTHS = frozenset({16, 24})

#? Samples read at a time, and the stop event looked at once a block.
BLOCK_FRAMES = 1 << 16

#? How much of the K-weighting's impulse response is worked out, and where it is cut: the rest of its
#? energy under TAIL_DB (2362 taps at 44.1 kHz, 50-54 ms at any rate).
IMPULSE_SECONDS = 0.25
TAIL_DB = -120.0

#? The rates whose loudness is measured decimated, and to what: src/resample.py's RESAMPLED_TO.
DECIMATED_TO = {88200: 44100, 176400: 44100, 352800: 44100, 96000: 48000, 192000: 48000, 384000: 48000}

#? A histogram as stored: (bin uint16, count uint32), little-endian, ascending, empty bins left out.
_PAIR = struct.Struct("<HI")

#? Each bin's lower edge as a mean square (libebur128's histogram_energy_boundaries), and the energy of
#? its centre (histogram_energies).
_EDGES = tuple(10 ** ((FLOOR_LUFS + i * BIN_LU - OFFSET) / 10) for i in range(BINS + 1))
_CENTRES = tuple(10 ** ((FLOOR_LUFS + (i + 0.5) * BIN_LU - OFFSET) / 10) for i in range(BINS))


class CannotMeasure(Exception):
    """This file can't be measured here: libsndfile can't read it, it isn't FLAC, or it has more than
    two channels. The song plays as it is."""


class Stopped(Exception):
    """The stop event was set: nobody needs the measurement any more."""


# ---------------------------------------------------------------- the key

def audio_key(streaminfo: bytes, version_key: str | None) -> str | None:
    """
    What a measurement is kept under: the song's AUDIO, not its file - `s:` and the SHA-256 of its
    STREAMINFO's 34 bytes, which hold the decoded audio's MD5, rate, channels, bits and length. A retag
    (deadwax's editor, Picard), a rename or an artist re-file leaves STREAMINFO alone, so a measurement
    survives every one. An encoder that skipped the MD5 left it all zeros, and two such songs of the
    same length would share a key: those are kept under their file's version instead (`v:` and the
    player cache's Version.key), measured again after a retag - None when there is no version to go by.
    """
    if len(streaminfo) != 34:
        return None
    if not any(streaminfo[18:34]):
        return f"v:{version_key}" if version_key else None
    return "s:" + hashlib.sha256(streaminfo).hexdigest()


# ---------------------------------------------------------------- the K-weighting

def k_coeffs(rate: int) -> tuple[tuple[list[float], list[float]], tuple[list[float], list[float]]]:
    """BS.1770-4's pre-filter (a high shelf) and its RLB high-pass, as (b, a) for each, re-derived for
    any rate as libebur128 does - BS.1770 gives coefficients for 48 kHz only."""
    f0, gain, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    k = math.tan(math.pi * f0 / rate)
    vh = 10 ** (gain / 20)
    vb = vh ** 0.4996667741545416
    a0 = 1 + k / q + k * k
    shelf = ([(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0],
             [1.0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0])
    f0, q = 38.13547087602444, 0.5003270373238773
    k = math.tan(math.pi * f0 / rate)
    a0 = 1 + k / q + k * k
    high_pass = ([1.0, -2.0, 1.0], [1.0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0])
    return shelf, high_pass


def biquad(samples, b, a) -> list[float]:
    """One biquad (transposed direct form II) run over `samples`, a sample at a time - plain Python,
    for the impulse response (and for checking the FFT against)."""
    out = []
    z1 = z2 = 0.0
    for value in samples:
        y = b[0] * value + z1
        z1 = b[1] * value - a[1] * y + z2
        z2 = b[2] * value - a[2] * y
        out.append(y)
    return out


@cache
def k_impulse(rate: int) -> tuple[float, ...]:
    """The K-weighting's impulse response at `rate`, cut where the rest of its energy is under TAIL_DB.
    Worked out once a rate."""
    n = max(1, int(rate * IMPULSE_SECONDS))
    (b1, a1), (b2, a2) = k_coeffs(rate)
    response = biquad(biquad([1.0] + [0.0] * (n - 1), b1, a1), b2, a2)
    total = sum(value * value for value in response)
    limit = total * 10 ** (TAIL_DB / 10)
    rest, cut = 0.0, n
    for i in range(n - 1, -1, -1):
        rest += response[i] * response[i]
        if rest >= limit:
            cut = i + 1
            break
    return tuple(response[:cut])


class _OverlapAdd:
    """
    The K-weighting applied to a stream of samples (samples, channels) by FFT overlap-add, in float32.
    The input is cut into segments of `block` samples however it arrives, so the output is the same
    bytes for any way of cutting the input; what each segment's convolution leaves past its end is
    carried into the next, and what the last leaves past the song's end is dropped.
    """

    def __init__(self, np, response, channels: int):
        self.np = np
        self.taps = len(response)
        nfft = 1 << 16
        while nfft < 4 * self.taps:
            nfft <<= 1
        self.nfft = nfft
        self.block = nfft - self.taps + 1
        self.spectrum = np.fft.rfft(np.asarray(response, dtype=np.float32), nfft)[:, None]
        self.carry = np.zeros((self.taps - 1, channels), dtype=np.float32)
        self.pending: list = []
        self.count = 0

    def push(self, samples) -> list:
        """Samples in; the filtered samples of every whole segment they complete out."""
        out = []
        if len(samples):
            self.pending.append(samples)
            self.count += len(samples)
        while self.count >= self.block:
            data = self.pending[0] if len(self.pending) == 1 else self.np.concatenate(self.pending)
            rest = data[self.block:]
            out.append(self._run(data[:self.block]))
            self.pending = [rest] if len(rest) else []
            self.count = len(rest)
        return out

    def finish(self) -> list:
        """The filtered samples of what is left - the song's last, part of a segment."""
        if not self.count:
            return []
        data = self.pending[0] if len(self.pending) == 1 else self.np.concatenate(self.pending)
        self.pending, self.count = [], 0
        return [self._run(data)]

    def _run(self, segment):
        np = self.np
        n = len(segment)
        filtered = np.fft.irfft(np.fft.rfft(segment, self.nfft, axis=0) * self.spectrum, self.nfft, axis=0)
        filtered = filtered[:n + self.taps - 1].astype(np.float32, copy=False)
        filtered[:self.taps - 1] += self.carry
        self.carry = filtered[n:n + self.taps - 1].copy()
        return filtered[:n]


def kfilter(np, samples, rate: int):
    """`samples` (samples, channels) K-weighted at `rate`, in one go - what _Meter streams."""
    run = _OverlapAdd(np, k_impulse(rate), samples.shape[1])
    pieces = run.push(np.ascontiguousarray(samples, dtype=np.float32)) + run.finish()
    return np.concatenate(pieces) if pieces else np.zeros((0, samples.shape[1]), dtype=np.float32)


# ---------------------------------------------------------------- the blocks and the histogram

def bin_of(energy: float) -> int | None:
    """The histogram bin a block of this mean square (channels summed and weighted) falls in, or None
    under the absolute gate. Past the top (+30 LUFS) it is the last bin, as libebur128 has it."""
    if not energy >= _EDGES[0]:
        return None
    low, high = 0, BINS
    while high - low > 1:
        middle = (low + high) // 2
        if energy >= _EDGES[middle]:
            low = middle
        else:
            high = middle
    return low


def _block_bins(np, energies):
    """bin_of() for an array of block energies at once: -1 for one under the gate."""
    edges = np.asarray(_EDGES)
    index = np.searchsorted(edges, energies, side="right") - 1
    index = np.minimum(index, BINS - 1)
    return np.where(energies >= edges[0], index, -1)


class _Meter:
    """The blocks of a K-weighted stream, counted into the histogram as each one completes."""

    def __init__(self, np, rate: int, channels: int):
        self.np = np
        self.filter = _OverlapAdd(np, k_impulse(rate), channels)
        #? 100 ms of samples: a block is four of them
        self.hop = max(1, round(rate * 0.1))
        #? mono heard in both ears: BS.1770's dual mono, +3.01 dB
        self.weight = 2.0 if channels == 1 else 1.0
        self.held: list = []
        self.held_count = 0
        #? the last three whole segments' sums of squares, for the next block
        self.recent: list[float] = []
        self.counts = [0] * BINS
        self.blocks = 0

    def push(self, samples) -> None:
        for filtered in self.filter.push(samples):
            self._segments(filtered)

    def finish(self) -> None:
        for filtered in self.filter.finish():
            self._segments(filtered)

    def _segments(self, filtered) -> None:
        np = self.np
        self.held.append(filtered)
        self.held_count += len(filtered)
        whole = self.held_count // self.hop
        if not whole:
            return
        data = self.held[0] if len(self.held) == 1 else np.concatenate(self.held)
        cut = whole * self.hop
        rest = data[cut:]
        self.held = [rest] if len(rest) else []
        self.held_count = len(rest)
        wide = data[:cut].astype(np.float64).reshape(whole, self.hop, data.shape[1])
        sums = [float(value) for value in (wide * wide).sum(axis=(1, 2))]
        run = self.recent + sums
        if len(run) < 4:
            self.recent = run
            return
        energies = np.array([sum(run[i:i + 4]) for i in range(len(run) - 3)]) * (self.weight / (4 * self.hop))
        for index in _block_bins(np, energies):
            self.blocks += 1
            if index >= 0:
                self.counts[int(index)] += 1
        self.recent = run[-3:]

    def histogram(self) -> tuple[tuple[int, int], ...]:
        return tuple((index, count) for index, count in enumerate(self.counts) if count)


# ---------------------------------------------------------------- a measurement

@dataclass(frozen=True)
class Measurement:
    """What deadwax keeps of a song: its loudest sample, its blocks' histogram, how many blocks (gated
    or not) and how long it is."""

    #? the largest |sample| of the song as it is, 1.0 being full scale
    peak: float
    #? (bin, count) for each bin with any block in it, ascending
    histogram: tuple[tuple[int, int], ...]
    blocks: int
    seconds: float

    @property
    def loudness(self) -> float:
        return loudness_of([self])


def pooled(measurements) -> list[int]:
    """The songs' histograms added up, bin by bin: what an album's loudness is read from."""
    counts = [0] * BINS
    for measurement in measurements:
        for index, count in measurement.histogram:
            counts[index] += count
    return counts


def loudness_of(measurements) -> float:
    """
    The integrated loudness, in LUFS, of these songs' blocks together - one song's, or an album's
    pooled - or -inf when no block is above the absolute gate (silence). libebur128's histogram mode:
    the relative gate is worked out from the bins' centres, and takes the bins whose centre is at or
    above it.
    """
    counts = pooled(measurements)
    total = sum(counts)
    if not total:
        return -math.inf
    relative = sum(count * centre for count, centre in zip(counts, _CENTRES)) / total * 10 ** (RELATIVE_GATE_LU / 10)
    if relative < _EDGES[0]:
        start = 0
    else:
        start = bin_of(relative) or 0
        if relative > _CENTRES[start]:
            start += 1
    kept = sum(counts[start:])
    if not kept:
        return -math.inf
    energy = sum(count * centre for count, centre in zip(counts[start:], _CENTRES[start:])) / kept
    return OFFSET + 10 * math.log10(energy)


def pack(histogram) -> bytes:
    """A histogram as the database keeps it."""
    return b"".join(_PAIR.pack(index, count) for index, count in histogram)


def unpack(blob: bytes) -> tuple[tuple[int, int], ...]:
    """A histogram as the database kept it. Raises ValueError for anything that isn't one."""
    if len(blob) % _PAIR.size:
        raise ValueError("a histogram is whole (bin, count) pairs")
    pairs = tuple(_PAIR.iter_unpack(blob))
    last = -1
    for index, count in pairs:
        if not last < index < BINS or count <= 0:
            raise ValueError("a histogram's bins ascend, each inside the range and counted")
        last = index
    return pairs


# ---------------------------------------------------------------- the gain

@dataclass(frozen=True)
class Gain:
    """The level applied to a song, and why it is that."""

    #? the gain applied, in dB, rounded down to 0.01
    gain_db: float
    #? what levelling alone asked for: REFERENCE_LUFS - the loudness (0 for silence)
    wanted_db: float
    #? the loudness it was worked out from, LUFS (-inf: silence), and the peak it is held under, dBFS
    loudness: float
    peak_db: float
    #? the peak held it under what was wanted
    held: bool


def gain_for(loudness: float, peak: float, reserve_db: float = 0.0) -> Gain:
    """
    The gain that takes a song (or an album) of `loudness` LUFS to REFERENCE_LUFS - held so its
    loudest sample, `peak` (1.0 = full scale), lands no higher than the largest 24-bit sample, with
    `reserve_db` more room besides (the resample's HEADROOM_DB, when the copy is resampled too: room
    for its own ringing). A sample peak is exact for what deadwax sends: every sample of the copy is
    known. Rounded DOWN to 0.01 dB, which can't take a sample past the limit. Silence asks for nothing.
    No cap on a positive gain but the peak: a quiet song is brought up until its loudest sample reaches
    full scale, as ReplayGain players do.
    """
    wanted = REFERENCE_LUFS - loudness if math.isfinite(loudness) else 0.0
    peak_db = 20 * math.log10(peak) if peak > 0 else -math.inf
    limit = FULL_DB - peak_db - reserve_db
    gain = min(wanted, limit)
    #? to the hundredth, downwards - and an integer count of hundredths, so the same gain is always the
    #? same float (the copy's key carries it, and its bytes are made from it)
    rounded = math.floor(round(gain * 100, 6)) / 100
    if rounded > limit:
        rounded = math.floor(gain * 100) / 100
    return Gain(gain_db=rounded, wanted_db=wanted, loudness=loudness, peak_db=peak_db, held=limit < wanted)


# ---------------------------------------------------------------- measuring a file

def measure_file(path, stop=None, block_frames: int = BLOCK_FRAMES) -> Measurement:
    """
    The FLAC song at `path` measured: read `block_frames` at a time, never held whole. `stop` (a
    threading.Event) is looked at once a block, and raises Stopped. Raises CannotMeasure for a file
    libsndfile can't read (a 20- or 32-bit FLAC, a damaged one), one it doesn't read as FLAC, or one of
    more than two channels. Runs in a worker thread: numpy's FFT and libsndfile let go of the GIL.
    """
    import numpy as np
    import soundfile as sf

    try:
        source = sf.SoundFile(str(path))
    except RuntimeError as e:
        raise CannotMeasure(f"libsndfile can't read it: {e}") from e
    with source:
        rate, channels, kind = source.samplerate, source.channels, source.format
        if kind != "FLAC":
            raise CannotMeasure(f"libsndfile reads it as {kind}, not FLAC")
        if channels not in MEASURED_CHANNELS:
            raise CannotMeasure(f"it has {channels} channels; only mono and stereo are measured")
        decimate = None
        measured_at = rate
        if DECIMATED_TO.get(rate) is not None:
            try:
                import soxr
            except Exception:
                #? without soxr, measured at its own rate: as exact, only slower
                soxr = None
            if soxr is not None:
                measured_at = DECIMATED_TO[rate]
                decimate = soxr.ResampleStream(rate, measured_at, channels, dtype="float32", quality="HQ")
        meter = _Meter(np, measured_at, channels)
        peak = 0.0
        frames = 0
        while True:
            if stop is not None and stop.is_set():
                raise Stopped()
            try:
                block = source.read(block_frames, dtype="float32", always_2d=True)
            except RuntimeError as e:
                raise CannotMeasure(f"libsndfile couldn't decode all of it: {e}") from e
            if not len(block):
                break
            frames += len(block)
            peak = max(peak, float(block.max()), -float(block.min()))
            meter.push(decimate.resample_chunk(block, last=False) if decimate is not None else block)
        if decimate is not None:
            meter.push(decimate.resample_chunk(np.zeros((0, channels), dtype=np.float32), last=True))
        meter.finish()
    return Measurement(peak=peak, histogram=meter.histogram(), blocks=meter.blocks, seconds=frames / rate if rate else 0.0)
