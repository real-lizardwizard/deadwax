"""
A hi-res FLAC song resampled to 48 kHz or 44.1 kHz, still lossless FLAC, for the player's
"Maximum quality: Up to 48 kHz" (1.1.0-player.6).

Why: the gapless player's one stream takes songs up to 48 kHz, so a 24/192 album - Dark Side of the
Moon, whose songs run into each other - played from the second player with a gap at every change.
James: "let's transcode it down to 48khz and push that under one condition. I don't want to lose any
sound quality." An iPhone's speaker, AirPods, Apple's headphone adapters and AirPlay all run at
48 kHz or less, so the phone converts a 192 kHz song down itself whatever deadwax sends; only an
external USB DAC might take more, which is why "Original" stays a choice on the page.

HOW THE CONDITION IS KEPT - each part measured before it was written:

  - Only songs ABOVE 48 kHz are touched, only at a whole ratio - 88.2/176.4/352.8 kHz to 44.1,
    96/192/384 kHz to 48 (2, 4 or 8) - and only 16- or 24-bit ones, the depths libsndfile 1.2.2 can
    open. Everything else is sent exactly as before, bit for bit (`output_rate()`).
  - libsoxr's VHQ preset (28-bit precision, linear phase) in float64: flat within 0.01 dB to
    22.24 kHz (48 kHz out) or 20.44 kHz (44.1 kHz out), 20 kHz changed by less than 3e-8 dB,
    aliasing at least 184 dB down. Rounded to 24 bits, +-0.5 LSB (-144.5 dBFS). Written as FLAC.
  - NEVER clipped, and the one change in level is the same for every song. A loud master whose
    peaks were cut flat when it was made rings past full scale once what was above 20 kHz is gone,
    and a 24-bit FLAC can't hold an over. Measured through this resample: 0.77 to 1.73 dB over on
    masters clipped 6 dB, up to 2.18 dB at 9 dB of clipping, up to 2.87 dB at 12. So every resampled
    song is lowered by HEADROOM_DB, 3 dB: room for every one of those, and one gain for all of an
    album's songs, so its joins stay exact. A song that would pass full scale even so is resampled a
    second time, lowered further by exactly enough, and the log says by how much: its joins with the
    songs beside it then step in level by that much. That takes a master clipped harder still - a
    real 24/192 recording clipped 18 dB went 2.66 to 3.11 dB over, 0.11 dB past the headroom in one
    ten-second stretch of the four measured.
  - The joins stay exact. A song cut from continuous music and resampled on its own clicks at each
    end (-24 to -6 dB against the signal), because the resampler assumes silence around it. So each
    song is resampled with CONTEXT - the last samples of the song before and the first of the song
    after - on ONE sample grid shared by the album (`album_phase()`): then the songs concatenate to
    what resampling the whole album at once gives, to float64's limit (-207 dB). src/album_context.py
    finds the neighbours and the phase; this module takes them as it is given them.

The resample streams: the song is read from disk a block at a time and never held whole (34 MiB at
the peak for a 7-minute 24/192 song, 2.5 s on an M2), and a threading.Event is looked at once a
block, so a make nobody waits for any more stops within one. What it writes goes through Python's
own file (`_Output`), so a disk that fills part-way is the OSError(ENOSPC) the player's cache clears
older songs for and tries once more, not the "System error." libsndfile would make of it.

numpy, soxr and soundfile are imported inside the functions that use them, never at the top: a
deadwax without them (run from source, say) starts as ever and sends every song as it is -
`missing_libraries()` says which are missing. Everything the tests pin about grids and counts is
plain Python.
"""

import io
import math
import struct
import time
from contextlib import contextmanager
from dataclasses import dataclass
from functools import cache
from pathlib import Path

from src.flac_mp4 import StreamInfo, _audio_ends, _crc16, _frame_header, _reach

#? Part of every resampled song's cache key (player_cache's Version.key_for). Bump it whenever what
#? this module writes changes - the soxr version or quality, the rounding - so a song resampled the
#? old way is never served under the new way's name. CONTEXT_SAMPLES and HEADROOM_DB are in the key
#? as they are (ResamplePlan.material()), so a change to either makes new files by itself.
RESAMPLE_FORMAT_VERSION = 1

#? How far every resampled song is lowered, in dB: the same for every song, and the only change in
#? level the resample makes. A master whose peaks were cut flat when it was made - every loud one -
#? rings past full scale once what was above 20 kHz is taken out, and a 24-bit FLAC can't hold an
#? over. Lowering each song by exactly its own over was tried first, and is exact for that song, but
#? a song lowered 1 dB beside one not lowered at all steps in level where they join: 11% of the
#? waveform, a tick at every such join. One gain for every song keeps an album's joins exact, and
#? 3 dB covers every master measured up to 12 dB of clipping - clipped 6 dB (0.77 to 1.73 dB over),
#? 9 dB (up to 2.18) and 12 dB (up to 2.87) - and three of four stretches of a real 24/192 recording
#? clipped 18 dB (2.66 to 2.90; the fourth went 3.11). 2 dB was tried first and a master clipped 9 dB
#? went past it. So
#? nothing clips either. It is also, in effect, what the phone does when it converts a hi-res song
#? down itself: in floating point, which keeps an over rather than clipping it, with its volume stage
#? lowering the whole song after. Only a freak still goes over 3 dB down - a master clipped 18 dB or
#? more - and it is lowered further by exactly enough, and logged (resample_file()).
HEADROOM_DB = 3.0

#? The rates resampled, and what to: whole ratios of 44.1 and 48 kHz only. Any other rate above
#? 48 kHz (64 kHz, 100 kHz) is sent as it is. ui/src/lib/streamWrap.ts holds the same table.
RESAMPLED_TO = {88200: 44100, 176400: 44100, 352800: 44100, 96000: 48000, 192000: 48000, 384000: 48000}

#? The source depths resampled. libsndfile 1.2.2 can't open a 20- or 32-bit FLAC at all (measured),
#? and 8-bit hi-res isn't a thing anybody has.
RESAMPLED_DEPTHS = frozenset({16, 24})

#? What the output always is: 24-bit, whatever the source, so the rounding after resampling is
#? 144 dB down rather than 96.
OUTPUT_BITS = 24

#? How much of each neighbour is taken as context, in input samples. The VHQ filter reaches +-548
#? input samples at 4:1 and +-1120 at 8:1 (to -200 dB); measured, 1024 samples of context left an
#? 8:1 join at -152 dB, and this reaches -215. Plenty at 2:1 and 4:1.
CONTEXT_SAMPLES = 16384

#? Samples read and resampled at a time: a third of a second of 192 kHz, 1 MiB of stereo float64.
#? The stop event is looked at once a block.
BLOCK_FRAMES = 1 << 16

#? 24-bit full scale, and the range a 24-bit sample may take.
_FULL = float(1 << 23)
_TOP = (1 << 23) - 1
_BOTTOM = -(1 << 23)

#? The libraries the resample needs, as they are imported.
LIBRARIES = ("numpy", "soxr", "soundfile")

#? A bound on the checksumming a context decode does, as a multiple of the bytes it was given plus
#? a floor: a real file sums each frame once (and the last against a tag or two), and anything that
#? needs more was built to be summed over and over - see _Sums.
_SUM_FACTOR, _SUM_FLOOR = 4, 1 << 20

#? A bound on the sync codes a context decode looks at that start no frame of the run it follows:
#? a floor, and one per this many bytes given - flac_mp4's FALSE_SYNC_BUDGET, for its reason. A real
#? file has about one every 90 KB. A stretch packed with valid headers that never chain has one every
#? few bytes, and every start tried looks at every header within a frame's reach of it: quadratic,
#? measured at 25 s for a head or tail of a 16 KB-frame stream, and days at what CONTEXT_READ_MAX
#? allows - in a worker thread no timeout can stop. Past this it is refused, so the work is linear.
_SYNC_FLOOR, _SYNC_DIVISOR = 4096, 256


class CannotResample(Exception):
    """This song, or this context, can't be resampled exactly here: the song is sent as it is, or
    the join goes without that side's context."""


class Stopped(Exception):
    """The stop event was set: nobody waits for this song any more."""


@cache
def _missing() -> str | None:
    gone = []
    for name in LIBRARIES:
        try:
            __import__(name)
        except Exception:
            #? an ImportError, or soundfile's OSError when libsndfile itself can't be loaded
            gone.append(name)
    return ", ".join(gone) or None


def missing_libraries() -> str | None:
    """Which of the audio libraries can't be imported, as a list in words, or None when all can.
    Tried once for the process."""
    return _missing()


def output_rate(source: int, cap: int | None, bits: int) -> int | None:
    """
    The rate a song recorded at `source` Hz and `bits` deep is resampled to under `cap` (48000 for
    "Up to 48 kHz", None for "Original") - or None, and it is sent exactly as it is.
    """
    if cap is None or source <= cap or bits not in RESAMPLED_DEPTHS:
        return None
    out = RESAMPLED_TO.get(source)
    return out if out is not None and out <= cap else None


def khz(rate: int) -> str:
    """A rate as people say it: 192 kHz, 44.1 kHz."""
    return f"{rate / 1000:g} kHz"


# ---------------------------------------------------------------- the album's grid

def album_phase(earlier: int, ratio: int) -> int:
    """
    Where the album's sample grid first falls in a song - the first of its input samples that
    lands on an output sample - from the total input samples of the earlier songs on the same
    grid. The NEGATIVE of the total, mod the ratio: the grid runs on from the album's first sample,
    so a song starting `earlier` samples in meets its next grid point (-earlier) mod ratio samples
    later. The opposite sign was measured joining at -14.7 dB and one sample long.
    """
    return (-earlier) % ratio


def output_count(n_in: int, phase: int, ratio: int) -> int:
    """How many output samples a song of `n_in` input samples has: the grid points phase,
    phase + ratio, ... that fall inside it."""
    return max(0, -(-(n_in - phase) // ratio))


def next_phase(phase: int, n_in: int, ratio: int) -> int:
    """The phase of the song after one of `n_in` samples at `phase`: where the grid's next point
    falls, counted from the next song's start. The same as album_phase() of the running total."""
    return (phase - n_in) % ratio


@dataclass(frozen=True)
class Neighbour:
    """A song beside the one resampled, on its album's grid, whose end or start is its context."""

    song_id: str
    #? its Version.key: in the resampled song's own key, so a neighbour whose audio changes makes it
    #? again
    version_key: str
    size: int
    #? its ETag or Last-Modified, sent as If-Range with each read of it: a file changed since it
    #? was looked at comes back whole, and isn't used
    validator: str | None
    info: StreamInfo
    #? where its first frame starts - needed only of the song after, whose start is read
    audio_offset: int | None


@dataclass(frozen=True)
class ResamplePlan:
    """Everything that decides a resampled song's bytes, but its own file."""

    max_rate: int
    source_rate: int
    out_rate: int
    channels: int
    bits: int
    total_samples: int
    phase: int = 0
    before: Neighbour | None = None
    after: Neighbour | None = None

    @property
    def ratio(self) -> int:
        return self.source_rate // self.out_rate

    @property
    def header(self) -> str:
        """What the answer says in X-Deadwax-Resampled: `<from>-<to>`, e.g. 192000-48000."""
        return f"{self.source_rate}-{self.out_rate}"

    @property
    def samples_out(self) -> int:
        return output_count(self.total_samples, self.phase, self.ratio)

    def material(self) -> list:
        """What goes in the cache key besides the song's own version: the neighbours by identity, so
        a new context is a new file - and the cap, the rate, the grid, the context length and the
        headroom."""
        def who(neighbour: Neighbour | None):
            return [neighbour.song_id, neighbour.version_key] if neighbour else None
        return [RESAMPLE_FORMAT_VERSION, self.max_rate, self.out_rate, self.phase, CONTEXT_SAMPLES,
                HEADROOM_DB, who(self.before), who(self.after)]

    def estimated_bytes(self, size: int) -> int:
        """About how big the resampled FLAC of a `size`-byte source comes out: the source scaled by
        the rate and the depth. What the memory cap on repackaging is judged by (the source itself is
        streamed from disk, never held)."""
        return size * self.out_rate * OUTPUT_BITS // (self.source_rate * self.bits)


@dataclass(frozen=True)
class Resampled:
    """What a resample did."""

    samples_in: int
    samples_out: int
    #? the loudest resampled sample before any lowering, in dBFS
    peak_db: float
    #? how far the song was lowered in all, in dB: HEADROOM_DB, like every resampled song - or more,
    #? for one that would have clipped even so
    lowered_db: float
    #? how much of that was beyond the headroom, in dB - None for all but a song clipped very hard
    #? when it was made, whose joins with the songs beside it step in level by as much
    beyond_db: float | None
    seconds: float


# ---------------------------------------------------------------- the resample

def resample_file(source: Path, target: Path, *, plan: ResamplePlan, before=None, after=None,
                  stop=None) -> Resampled:
    """
    The FLAC song at `source` resampled as `plan` says, written to `target` as a 24-bit FLAC.

    `before` and `after` are the last samples of the song before and the first of the song after,
    float64 (samples, channels), or None where there is none or it couldn't be had - then that end
    is resampled against zeros on the album's grid, which keeps the song's own length and phase
    right, only the join isn't exact. `stop` (a threading.Event) is looked at once a block, and
    raises Stopped; the caller deletes `target`. Raises CannotResample for a file libsndfile can't
    read, that isn't what the plan says it is, or that is too short to reach the album's grid; and a
    write the disk refuses as the OSError it is - ENOSPC for a disk that filled. Runs in a worker
    thread.

    Every song comes out lowered by HEADROOM_DB, and one that would pass full scale even so is
    resampled a second time, lowered further by exactly enough (Resampled.beyond_db).
    """
    import numpy as np
    import soundfile as sf

    began = time.monotonic()
    try:
        with sf.SoundFile(str(source)) as f:
            rate, channels, frames, kind = f.samplerate, f.channels, f.frames, f.format
    except RuntimeError as e:
        #? soundfile's LibsndfileError, a RuntimeError: a 20- or 32-bit FLAC, a damaged one
        raise CannotResample(f"libsndfile can't read it: {e}") from e
    if kind != "FLAC":
        raise CannotResample(f"libsndfile reads it as {kind}, not FLAC")
    if (rate, channels) != (plan.source_rate, plan.channels):
        raise CannotResample(f"it is {rate} Hz with {channels} channel(s), where its STREAMINFO said "
                             f"{plan.source_rate} Hz with {plan.channels}")
    if frames != plan.total_samples:
        raise CannotResample(f"libsndfile counts {frames} samples where its STREAMINFO said {plan.total_samples}")
    if not 0 <= plan.phase < plan.ratio:
        raise CannotResample(f"a phase of {plan.phase} doesn't fall inside a ratio of {plan.ratio}")
    if plan.samples_out == 0:
        #? a song a few samples long that ends before the album's grid next falls in it: nothing to
        #? write, and an empty FLAC is no answer to anything
        raise CannotResample(f"it is {plan.total_samples} sample(s) long, and none of them falls on the "
                             f"album's {khz(plan.out_rate)} grid, so there is nothing to send")

    pre = _fit(np, before, channels, "pre")
    post = _fit(np, after, channels, "post")
    gain = 10 ** (-HEADROOM_DB / 20)
    high, low, over = _pass(source, target, plan, pre, post, gain, stop)
    peak = max(high, -low)
    lowered, beyond = HEADROOM_DB, None
    if over:
        #? Past full scale even with the headroom - a master clipped very hard. Lower the whole song
        #? by exactly enough that its loudest sample lands on full scale, and resample again: the
        #? first pass kept nothing but its peaks. It is lowered more than the songs beside it, so
        #? their joins step in level by the difference, which the caller says.
        gain = min(_TOP / (high * _FULL) if high > 0 else 1.0, _BOTTOM / (low * _FULL) if low < 0 else 1.0)
        again = _pass(source, target, plan, pre, post, gain, stop)
        if again != (high, low, False):
            raise CannotResample("the second pass didn't resample exactly as the first did")
        lowered = -20 * math.log10(gain)
        beyond = lowered - HEADROOM_DB
    return Resampled(samples_in=plan.total_samples, samples_out=plan.samples_out,
                     peak_db=20 * math.log10(peak) if peak > 0 else -math.inf, lowered_db=lowered,
                     beyond_db=beyond, seconds=time.monotonic() - began)


def _fit(np, context, channels: int, side: str):
    """A neighbour's samples as float64 (samples, channels), the CONTEXT_SAMPLES nearest the join -
    or None when there are none, or they aren't this song's channel count."""
    if context is None or len(context) == 0:
        return None
    context = np.asarray(context, dtype=np.float64)
    if context.ndim == 1:
        context = context[:, None]
    if context.shape[1] != channels:
        return None
    return np.ascontiguousarray(context[-CONTEXT_SAMPLES:] if side == "pre" else context[:CONTEXT_SAMPLES])


def _pass(source: Path, target: Path, plan: ResamplePlan, pre, post, gain: float,
          stop) -> tuple[float, float, bool]:
    """
    One pass: resample the song and write it, quantised with `gain` (the headroom's on the first
    pass). The loudest and quietest resampled values before that, 1.0 being full scale, and whether
    any of them, rounded, fell outside 24 bits - and so was clipped, on a pass about to be done again.

    What goes into the resampler is `lead + song + tail`:
      - `lead`: P samples of the song before, with P = -phase (mod ratio), so that output j of the
        run lands exactly on the song's grid point phase + j x ratio once the first outputs are
        dropped. Without the song before, that many zeros - with none at all output 0 would land on
        the song's first sample, not on its phase.
      - `tail`: the song after, and then `ratio` zeros whatever: soxr gives round-half-up(N / ratio)
        samples, one short of the grid's count for some lengths, and flushing past the end with
        silence gives the same samples, only enough of them.
    soxr is time-aligned (an impulse at input 4000 comes out at output 1000 at 4:1), and the
    stream's output is bit for bit its one-shot output, however the input is cut up.
    """
    import numpy as np
    import soundfile as sf
    import soxr

    ratio, channels, phase = plan.ratio, plan.channels, plan.phase
    if pre is not None:
        take = len(pre) - ((len(pre) + phase) % ratio)
        lead = pre[len(pre) - take:] if take > 0 else np.zeros(((-phase) % ratio, channels))
    else:
        lead = np.zeros(((-phase) % ratio, channels))
    skip = (len(lead) + phase) // ratio
    want = output_count(plan.total_samples, phase, ratio)
    silence = np.zeros((ratio, channels))
    tail = silence if post is None else np.concatenate([post, silence])
    stream = soxr.ResampleStream(plan.source_rate, plan.out_rate, channels, dtype="float64", quality="VHQ")
    scale = _FULL * gain
    high = low = 0.0
    over = False
    written = 0

    def emit(out, y) -> None:
        nonlocal skip, written, high, low, over
        if skip:
            dropped = min(skip, len(y))
            y = y[dropped:]
            skip -= dropped
        y = y[:want - written]
        if not len(y):
            return
        high = max(high, float(y.max()))
        low = min(low, float(y.min()))
        q = np.rint(y * scale)
        over = over or bool(q.max() > _TOP or q.min() < _BOTTOM)
        #? only ever acts on a first pass that is about to be done again, lowered further: without it
        #? a value past 24 bits would overflow the shift below
        np.clip(q, _BOTTOM, _TOP, out=q)
        out.write(q.astype(np.int32) << 8)
        written += len(y)

    with sf.SoundFile(str(source)) as song, _flac_output(target, plan.out_rate, channels) as out:
        emit(out, stream.resample_chunk(np.ascontiguousarray(lead), last=False))
        #? exactly the samples STREAMINFO counts: a tag after the audio must not add any
        left = plan.total_samples
        while left:
            if stop is not None and stop.is_set():
                raise Stopped()
            try:
                block = song.read(min(BLOCK_FRAMES, left), dtype="float64", always_2d=True)
            except RuntimeError as e:
                #? soundfile's LibsndfileError: a frame libFLAC can't decode - a damaged file, down to
                #? one flipped bit (its CRC). It is the same on every try, so it is refused and
                #? remembered, not downloaded and resampled again for each request. Only the read:
                #? anything the output raises is the disk's, or a bug
                raise CannotResample(f"libsndfile couldn't decode all of it: {e}") from e
            if not len(block):
                raise CannotResample(f"the song ended {left} samples short of what its STREAMINFO says")
            left -= len(block)
            emit(out, stream.resample_chunk(block, last=False))
        if stop is not None and stop.is_set():
            raise Stopped()
        emit(out, stream.resample_chunk(np.ascontiguousarray(tail), last=True))
    if written != want:
        raise CannotResample(f"{written} samples came out where the grid has {want}")
    return high, low, over


def _open_output(target: Path):
    """The file the resampled FLAC is written to."""
    return open(target, "wb")


class _Output:
    """
    The resampled FLAC's file as libsndfile writes it: through Python's own file, so that a write
    the disk refuses is kept as the OSError it is.

    Given a path, libsndfile makes any failed write "System error." in a RuntimeError - a full disk
    and a broken one alike - and a disk that filled during the resample was taken for a bug: the make
    logged it and gave up, where a disk that fills is what it clears older songs and tries once more
    for. Worse, a write that fails at the very last frame, which libsndfile writes as the file
    closes, it doesn't report at all: measured with a file-size limit, the FLAC came out a byte short
    and nothing was raised. Through this, the make gets the OSError itself, ENOSPC for a full disk,
    wherever it happened. Measured: the bytes written are the same, byte for byte, and so is the
    time. Nothing may be raised back into libsndfile (cffi would print it and carry on), so an error
    is kept and libsndfile told nothing was written, which stops it; _flac_output() raises what was
    kept.
    """

    def __init__(self, file):
        self.file = file
        self.error: Exception | None = None

    def _failed(self, error: Exception) -> None:
        if self.error is None:
            self.error = error

    def write(self, data: bytes) -> int:
        try:
            #? a buffered file writes all of it or raises: never fewer bytes without saying why
            return self.file.write(data)
        except Exception as e:
            self._failed(e)
            return 0

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        try:
            #? flushes first - where the last of the frames can find the disk full
            return self.file.seek(offset, whence)
        except Exception as e:
            self._failed(e)
            return -1

    def tell(self) -> int:
        try:
            return self.file.tell()
        except Exception as e:
            self._failed(e)
            return -1


@contextmanager
def _flac_output(target: Path, rate: int, channels: int):
    """`target` open for libsndfile to write a 24-bit FLAC into - see _Output. A write the disk
    refused comes out as the OSError it was, whatever libsndfile made of it: an AssertionError from
    soundfile, which counts the frames written; a RuntimeError, at the open; or nothing at all, for
    the last frame, written as the file closes (or anywhere, with Python's asserts off)."""
    import soundfile as sf

    with _open_output(target) as file:
        output = _Output(file)
        try:
            with sf.SoundFile(output, "w", rate, channels, subtype="PCM_24", format="FLAC") as out:
                yield out
        except Exception as e:
            if output.error is None:
                raise
            raise output.error from e
        if output.error is not None:
            raise output.error


# ---------------------------------------------------------------- context from part of a file
#
# A neighbour's context is read from a small byte range of its file - its last hundred kilobytes or
# so, or its first - never the whole of it. libsndfile won't decode a FLAC cut short (it reads ahead
# and loses sync), nor a tail behind the original STREAMINFO (it seeks to frame 0 and fails). What it
# does decode, exactly, every time (1,120 randomised decodes, exact or refused and never wrong): a
# minimal FLAC of its own - 'fLaC', STREAMINFO as the only block, its total set to what the frames
# given hold and its MD5 zeroed, then whole frames untouched, numbered from wherever they are in the
# song, which libFLAC doesn't mind. So the whole frames are found first, with the muxer's header rules
# (src/flac_mp4.py) and each one's CRC-16, and only those go in.

@dataclass(frozen=True)
class Frame:
    """One whole frame found in the bytes given."""

    start: int          # where it starts in those bytes
    end: int
    first: int          # its first sample's number in the song
    block: int          # how many samples it holds


class _Sums:
    """The CRC-16s one search asks for, within a budget of bytes summed: a real file sums each frame
    once, and a stretch built full of false headers - a Soulseek peer's file is anybody's - is
    refused instead of holding a worker thread."""

    def __init__(self, data: bytes):
        self.data = data
        self.left = _SUM_FACTOR * len(data) + _SUM_FLOOR

    def zero(self, start: int, end: int) -> bool:
        self.left -= end - start
        if self.left < 0:
            raise CannotResample("far too much checksumming for a context")
        return _crc16(self.data[start:end]) == 0


def whole_frames(data: bytes, pos: int, info: StreamInfo, at_end: bool) -> list[Frame]:
    """
    The whole frames in `data` from the first real one at or after `pos`.

    A frame is taken only when its header checks out (flac_mp4's rules: every field agrees with
    STREAMINFO, the number is coded the shortest way, CRC-8), the header after it follows carrying
    the next number, and the frame's CRC-16 over everything between the two comes to zero. `at_end`:
    `data` ends where the file does, so the last frame runs to the end (or to a tag appended to it),
    checked by its CRC-16 too; otherwise the last frame, whose end can't be checked, is left out. An
    empty list when nothing in `data` can be read with certainty.

    Bounded, for a file built to hold a worker thread: every sync code that starts no frame of the
    run being followed - a candidate that isn't the next frame, a start that leads nowhere - is
    counted, and past _SYNC_FLOOR plus one per _SYNC_DIVISOR bytes it is refused (CannotResample);
    the checksumming has its own bound (_Sums).
    """
    reach = _reach(info)
    sums = _Sums(data)
    syncs = (b"\xff\xf8", b"\xff\xf9")
    budget = _SYNC_FLOOR + len(data) // _SYNC_DIVISOR

    def spend() -> None:
        nonlocal budget
        budget -= 1
        if budget < 0:
            raise CannotResample("far too many sync codes that start no frame in a context")

    def next_sync(at: int, sync: bytes | None = None) -> int:
        if sync is not None:
            return data.find(sync, at)
        found = [p for p in (data.find(s, at) for s in syncs) if p >= 0]
        return min(found) if found else -1

    def chain(start: int, header) -> list[Frame] | None:
        fixed = data[start + 1] == 0xF8
        sync = data[start:start + 2]
        frames = []
        at, (number, block, length) = start, header
        while True:
            wanted = number + (1 if fixed else block)
            first = number * info.max_block if fixed else number
            candidate = next_sync(at + length, sync)
            found = None
            while 0 <= candidate and candidate - at <= reach:
                following = _frame_header(data, candidate, info)
                if following is not None and following[0] == wanted and sums.zero(at, candidate):
                    found = (candidate, following)
                    break
                spend()
                candidate = next_sync(candidate + 1, sync)
            if found is None:
                if at_end:
                    for end in sorted(_audio_ends(data, at)):
                        if end - at <= reach and sums.zero(at, end):
                            frames.append(Frame(at, end, first, block))
                            return frames
                    return None
                return frames or None
            frames.append(Frame(at, found[0], first, block))
            at, (number, block, length) = found

    at = next_sync(pos)
    while at >= 0:
        header = _frame_header(data, at, info)
        if header is not None:
            got = chain(at, header)
            if got:
                return got
        spend()
        at = next_sync(at + 1)
    return []


def _decode(data: bytes, frames: list[Frame], info: StreamInfo):
    """A run of whole frames decoded through libsndfile, as float64 exactly as the whole file
    decodes - see the note above whole_frames()."""
    import soundfile as sf

    raw = bytearray(info.raw)
    packed = int.from_bytes(raw[10:18], "big")
    total = sum(frame.block for frame in frames)
    raw[10:18] = ((packed & ~0xFFFFFFFFF) | total).to_bytes(8, "big")
    raw[18:34] = bytes(16)
    mini = b"".join((b"fLaC", bytes((0x80, 0, 0, 34)), bytes(raw), data[frames[0].start:frames[-1].end]))
    try:
        with sf.SoundFile(io.BytesIO(mini)) as f:
            out = f.read(dtype="float64", always_2d=True)
    except RuntimeError as e:
        raise CannotResample(f"libsndfile couldn't decode its frames: {e}") from e
    if len(out) != total:
        raise CannotResample(f"decoded {len(out)} samples of {total}")
    return out


def head_bytes(info: StreamInfo, n: int = CONTEXT_SAMPLES) -> int:
    """How many bytes from a song's first frame certainly hold the frames of its first `n` samples
    and the header of the frame after them."""
    return (-(-n // info.max_block) + 1) * _reach(info) + 32


def tail_bytes(info: StreamInfo, n: int = CONTEXT_SAMPLES) -> int:
    """How many bytes from the end of a song's file certainly hold whole frames covering its last
    `n` samples (a tag appended to it aside - see trailer_length())."""
    return (-(-n // info.max_block) + 2) * _reach(info)


def trailer_length(tail: bytes) -> int:
    """How many bytes the tags appended to a FLAC file say they take up - an ID3v1 (and its TAG+
    extension) and an APEv2 before it - read from the last bytes of the file, even when the tags
    run further back than `tail` goes. The same tags flac_mp4's _audio_ends() looks for."""
    end, length = len(tail), 0
    if end >= 128 and tail[end - 128:end - 125] == b"TAG":
        length = 128
        if end - 128 >= 227 and tail[end - 355:end - 351] == b"TAG+":
            length += 227
    end -= length
    if end >= 32 and tail[end - 32:end - 24] == b"APETAGEX":
        size, flags = struct.unpack("<I4xI", tail[end - 20:end - 8])
        length += size + (32 if flags & 0x80000000 else 0)
    return length


def head_samples(info: StreamInfo, data: bytes, n: int = CONTEXT_SAMPLES, whole_file: bool = False):
    """
    The first `n` samples of a song (all of it, when it is shorter), float64 (samples, channels),
    from bytes of its file starting at its first frame. `whole_file`: `data` runs to the end of the
    file. Raises CannotResample when they can't be had exactly.
    """
    frames = whole_frames(data, 0, info, at_end=whole_file)
    if not frames or frames[0].start != 0 or frames[0].first != 0:
        raise CannotResample("no whole frames where its audio starts")
    got = 0
    for index, frame in enumerate(frames):
        got += frame.block
        if got >= n:
            frames = frames[:index + 1]
            break
    else:
        if not whole_file and not (info.total_samples and got >= info.total_samples):
            raise CannotResample(f"the bytes read hold {got} samples of the {n} wanted")
    return _decode(data, frames, info)[:n]


def tail_samples(info: StreamInfo, tail: bytes, n: int = CONTEXT_SAMPLES):
    """
    The last `n` samples of a song (all of it, when it is shorter), float64 (samples, channels),
    from its STREAMINFO and the last bytes of its file. Raises CannotResample when they can't be had
    exactly.
    """
    frames = whole_frames(tail, 0, info, at_end=True)
    if not frames:
        raise CannotResample("no whole frames in the end of its file")
    held = sum(frame.block for frame in frames)
    if info.total_samples and frames[0].first + held != info.total_samples:
        raise CannotResample(f"the frames read end at sample {frames[0].first + held}, where its "
                             f"STREAMINFO says {info.total_samples}")
    #? only the frames needed are decoded
    while len(frames) > 1 and held - frames[0].block >= n:
        held -= frames[0].block
        frames = frames[1:]
    if held < n and frames[0].first != 0:
        raise CannotResample(f"the bytes read hold {held} samples of the {n} wanted")
    return _decode(tail, frames, info)[-n:]
