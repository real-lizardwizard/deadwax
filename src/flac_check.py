"""
Whether a FLAC that came from Soulseek is whole, before it is filed - damaged downloads (asked for, 27 Nov).

23 FLACs once came from two peers with 807 to 6,140 stale bytes after the end of their audio: a sharer's copy loop
had written its whole 6,144-byte buffer on its last, short read. deadwax filed them as they were, and the iPhone
app's sound check threw each copy away and asked again, about 40 times a song in a week. James: "Let's avoid
trimming for now and just move on to the next peer with some sort of message about it so I know what happened."
So a download's FLACs are checked before anything is filed (organizer.plan_organization), one damaged song refuses
the whole album from that peer, and the job moves to its next source (poller.py). Nothing here changes a byte.

A FLAC is DAMAGED when one of these is certain:

- STALE_TAIL, "extra data after the end": the frame holding the stream's last sample (STREAMINFO's total) checks
  out - its CRC-16 comes to zero - before the end of the file, and what follows is not an ID3v1 or APEv2 tag. Zero
  bytes at the very end count as extra too, as flac_mp4 counts them, but only past what a silent last frame ends in
  itself (review: digital silence is a CONSTANT subframe of zeros per channel, and with a CRC-16 of 0x0000 the frame
  ends in a run of zeros - eight, for 16-bit stereo - that no sum can tell from zeros appended: UNCHECKED, _silent).
- CUT_SHORT: the file ends before the stream holds every sample STREAMINFO counts - inside the last frame, or
  frames before it - or inside its own metadata.
- DAMAGED_INSIDE: a frame fails its CRC-16 against the next frame's header, or no frame header follows a frame
  where one must, or the last frame checks out nowhere a frame of this stream could end, or there is no valid frame
  where the metadata ends.

How the true end is found (the stale-tail report's "Detecting E safely", steps 1-4 - its step 5, an MD5 of the
decoded audio, is for trimming, which is not done): STREAMINFO read; frame headers walked - sync code, CRC-8,
numbers in sequence - each frame checked by its CRC-16 against the next header, to the frame holding the last
sample; then that frame's CRC-16 summed byte by byte, and the audio ends where it comes to zero. A chance zero
inside the real frame (one byte in 65,536) is never taken for the end while the end of the file or a tag's start
also checks out, so a whole file always reads as whole; and a zero followed by a frame header (a whole stale frame
after the real end sums to zero too) is a frame's end with another after it, so the tail is extra.

A clean file, and one with ID3v2 in front or tags behind (the report's Daft Punk files), reads OK and is filed
exactly as before. The tags behind are stripped from the end one at a time, again and again (_tag_ends), each an
end the audio may have: ID3v1 (with its "TAG+" extension), APEv2 (with or without its header), and ID3v2 written
at the end with its "3DI" footer - in any order, ID3v1 written twice included. Everything this can't judge with
certainty is UNCHECKED and filed as before too: not a FLAC at all (the tests' "fLaC"-less stand-ins, a macOS ._
file), STREAMINFO not valid, more samples than STREAMINFO counts, far more sync codes than real FLAC has, far more
summing than one pass over the file (SUM_BUDGET: a file built with thousands of copies of the next frame's header
inside a frame would be summed from its start to every one), over 1 GiB - and (review, App Design's ruling) a first
frame numbered other than 0: a song cut from a longer stream with ffmpeg's stream copy keeps its frame numbers and
plays everywhere, so it is not refused. A refusal moves the download to another source, so it is said only when
sure.

Every header is read by flac_mp4's own parser (_skip_id3v2, _read_metadata, _frame_header) and the last frame's
zeros found by its _Checksums, all with its CRC-16; the tags behind the audio are found here (_tag_ends), since
flac_mp4's _audio_ends - the player's - takes only one ID3v1 and one APEv2, and the player is left as it is. Only a
whole frame's check is done another way here (_sums_to_zero): the same CRC as polynomial division on Python integers,
about ten times flac_mp4's byte loop - this sums every frame of every song of an album, where the player sums only
the last; tests/test_flac_check.py holds it to flac_mp4._crc16.

Pure: bytes in, a verdict out - but check_file(), which reads one file a window at a time (_Reader, review: never
the whole file in memory) and calls check() on it.
"""

import os
import struct
from dataclasses import dataclass, replace
from pathlib import Path

from src.flac_mp4 import (FALSE_SYNC_BUDGET, HEADER_MAX, MAX_INPUT_BYTES, NotFlac, Truncated, Unsupported, _Checksums,
                          _crc16, _frame_header, _reach, _read_metadata, _skip_id3v2)

OK = "ok"
STALE_TAIL = "stale_tail"
CUT_SHORT = "cut_short"
DAMAGED_INSIDE = "damaged_inside"
UNCHECKED = "unchecked"
#? the verdicts that refuse a download, in the order the reason names them (damage_reason)
DAMAGED = (STALE_TAIL, CUT_SHORT, DAMAGED_INSIDE)

#? both sync codes - the fixed-block stream's and the variable-block one's (flac_mp4's _SYNCS)
_SYNCS = (b"\xff\xf8", b"\xff\xf9")

#? (review) How much the walk may sum, in bytes: a floor and so many times the file. A whole file sums each frame
#? once - one pass - and a false header carrying the next frame's number (one in many millions of bytes) a frame
#? more; a file planted with thousands of them inside one frame would be summed from the frame's start to each,
#? quadratic in the frame (8,000 in a 131 KB frame took over a second). Past this it is UNCHECKED - filed as before,
#? never refused - so the walk stays linear in the file's size, capped.
SUM_BUDGET = (4 << 20, 2)
#? the most tags stripped from the end of a file (_tag_ends): more than any tagger writes, fewer than a file of
#? nothing but "TAG"s could make it try
TAGS_BEHIND = 8


@dataclass(frozen=True)
class Verdict:
    """What check() found: `kind` (OK, one of DAMAGED, or UNCHECKED), `why` in plain words for the log, and for a
    stale tail how many bytes follow the end of the audio."""

    kind: str
    why: str = ""
    extra: int = 0

    @property
    def damaged(self) -> bool:
        return self.kind in DAMAGED


# --- the CRC-16 of a whole frame, quickly ------------------------------------------------------------------

#? flac_mp4's CRC-16 polynomial, x^16 + x^15 + x^2 + 1 - its 0x8005 with the top term
_POLY = 0x18005


def _carryless(a: int, b: int) -> int:
    product = 0
    while b:
        if b & 1:
            product ^= a
        a <<= 1
        b >>= 1
    return product


def _reduce(a: int) -> int:
    while a.bit_length() > 16:
        a ^= _POLY << (a.bit_length() - 17)
    return a


def _folds() -> tuple[tuple[int, ...], ...]:
    """For m = 0..47: the powers of x set in x^(2^m) mod _POLY - what a fold at 2^m bits multiplies by."""
    found, power = [], 2
    for _ in range(48):
        found.append(tuple(bit for bit in range(16) if power >> bit & 1))
        power = _reduce(_carryless(power, power))
    return tuple(found)


_FOLDS = _folds()
#? a stretch this short is summed by flac_mp4's own loop, and a long one is folded down to it
_SMALL_BYTES = 96


def _sums_to_zero(data, start: int, end: int) -> bool:
    """
    Whether data[start:end]'s CRC-16 is zero - flac_mp4._crc16(data[start:end]) == 0, which is how a whole frame,
    its own CRC-16 included, checks out.

    FLAC's CRC-16 starts at zero and reflects nothing, so it is the bytes read as a polynomial over GF(2) - the
    first byte's top bit the highest power - times x^16, modulo _POLY; and since x^16 shares no factor with _POLY,
    it is zero exactly when the bytes themselves divide by _POLY. That is found by folding: a = hi * x^k + lo is
    lo + hi * (x^k mod _POLY) modulo _POLY, a few shifts and XORs of a Python integer, which halves a at each k =
    2^m until it is short enough for _crc16 to finish. Each fold keeps a's remainder, so the answer is _crc16's.
    """
    if end - start <= _SMALL_BYTES:
        return _crc16(data[start:end]) == 0
    a = int.from_bytes(data[start:end], "big")
    bits = a.bit_length()
    m = len(_FOLDS) - 1
    while bits > _SMALL_BYTES * 8 and m >= 0:
        k = 1 << m
        if k + 16 >= bits:
            m -= 1
            continue
        high = a >> k
        a &= (1 << k) - 1
        for power in _FOLDS[m]:
            a ^= high << power
        bits = a.bit_length()
        m -= 1
    return _crc16(a.to_bytes((bits + 7) // 8, "big")) == 0


# --- the walk -----------------------------------------------------------------------------------------------

def check(data: bytes) -> Verdict:
    """Whether the FLAC file `data` is whole (OK), damaged (one of DAMAGED), or not one this can judge (UNCHECKED)."""
    if len(data) > MAX_INPUT_BYTES:
        return Verdict(UNCHECKED, f"larger than {MAX_INPUT_BYTES >> 20} MiB")
    try:
        info, first = _read_metadata(data, _skip_id3v2(data))
    except Truncated:
        return Verdict(CUT_SHORT, "the file ends inside its metadata")
    except (NotFlac, Unsupported) as e:
        return Verdict(UNCHECKED, str(e))
    if first >= len(data):
        if info.total_samples:
            return Verdict(CUT_SHORT, "there is no audio after the metadata")
        return Verdict(UNCHECKED, "no audio, and STREAMINFO gives no length")
    try:
        return _walk(data, first, info)
    except Unsupported as e:
        #? a budget spent (far too many sync codes, or far too much summing): not something to refuse a peer for
        return Verdict(UNCHECKED, str(e))


class _Spend:
    """The walk's summing, counted against SUM_BUDGET: Unsupported once it is spent."""

    def __init__(self, size: int):
        self.left = SUM_BUDGET[0] + SUM_BUDGET[1] * size

    def __call__(self, count: int) -> None:
        self.left -= count
        if self.left < 0:
            raise Unsupported("far too much summing for a file of its size")


def _walk(data, first: int, info) -> Verdict:
    """Frame by frame from the first, each checked by its CRC-16 against the next one's header, to the frame
    holding the last sample STREAMINFO counts - or, when it counts none, the last frame there is. A first frame
    numbered other than 0 is UNCHECKED (the module's docstring: App Design's ruling)."""
    sync = bytes(data[first:first + 2])
    got = _frame_header(data, first, info) if sync in _SYNCS else None
    if got is None:
        return Verdict(DAMAGED_INSIDE, "there is no valid audio frame where the metadata ends")
    if got[0] != 0:
        #? (review) cut from a longer stream - ffmpeg's stream copy keeps the numbers - and it plays: doubt never refuses
        return Verdict(UNCHECKED, f"its first frame is numbered {got[0]}, not 0")
    fixed = sync == _SYNCS[0]
    #? the most bytes a frame of this stream can take up WHATEVER STREAMINFO says its largest is: every sample
    #? stored as it is (flac_mp4._reach with no largest frame given) - a refusal must not rest on an encoder's figure
    reach = _reach(replace(info, max_framesize=0))
    total = info.total_samples
    budget = FALSE_SYNC_BUDGET[0] + len(data) // FALSE_SYNC_BUDGET[1]
    spend = _Spend(len(data))
    pos, index, samples = first, 0, 0
    number, block, length = got
    while True:
        if total and samples + block >= total:
            if samples + block > total:
                return Verdict(UNCHECKED, f"its frames hold more samples than the {total} STREAMINFO counts")
            return _ending(data, pos, length, reach, info, _expected(pos - first, samples, block))
        wanted = number + 1 if fixed else number + block
        at, seen, budget = _next_frame(data, pos, length, sync, wanted, info, budget, spend)
        if at is None:
            if seen:
                return Verdict(DAMAGED_INSIDE, f"frame {index} fails its checksum")
            if not total:
                return _ending(data, pos, length, reach, info, _expected(pos - first, samples, block))
            if len(data) - pos <= reach + HEADER_MAX:
                return Verdict(CUT_SHORT, f"the file ends {total - samples} samples before the end of the stream")
            return Verdict(DAMAGED_INSIDE, f"no frame follows frame {index}")
        samples += block
        index += 1
        pos = at
        number, block, length = _frame_header(data, at, info)


def _next_frame(data, pos: int, length: int, sync: bytes, wanted: int, info, budget: int, spend: _Spend):
    """(where the frame after the one at `pos` begins or None, whether a header carrying its number was seen at
    all, the budget left). A header counts only when it is right in every particular (_frame_header), carries the
    next number, and the frame before it checks out to it - each sum counted against `spend` (SUM_BUDGET)."""
    seen = False
    at = data.find(sync, pos + length)
    while at >= 0:
        got = _frame_header(data, at, info)
        if got is not None and got[0] == wanted:
            seen = True
            spend(at - pos)
            if _sums_to_zero(data, pos, at):
                return at, seen, budget
        else:
            budget -= 1
            if budget < 0:
                raise Unsupported("far too many sync codes that start no frame")
        at = data.find(sync, at + 1)
    return None, seen, budget


def _expected(audio_before: int, samples_before: int, block: int) -> int | None:
    """About how many bytes the last frame should take, from the bytes a sample took in every frame before it."""
    return audio_before * block // samples_before if samples_before else None


#? the sharer's copy loop the report found: its whole 6,144-byte buffer written on the last, short read, so what
#? follows the end is a copy of the stretch 6,144 bytes before it
COPY_BUFFER = 6144


def _ending(data, pos: int, length: int, reach: int, info, expected: int | None) -> Verdict:
    """Where the stream's last frame, at `pos`, ends - and so whether anything that isn't a tag comes after it.
    `expected` is about how long that frame should be (_expected), None with no frame before it."""
    size = len(data)
    limit = min(size, pos + reach)
    #? every place within a frame's reach where the sum from the frame's start comes to zero (flac_mp4's _Checksums)
    zeros = sorted(_Checksums(data).zeros(pos, list(range(pos + length + 1, limit + 1)))) if limit > pos + length else []
    #? a zero with a frame header after it is a frame's end with another after it - a whole stale frame sums to zero
    framed = [at for at in zeros if at < size and _header_at(data, at, info)]
    for end in _tag_ends(data, pos):
        if end not in zeros or any(at < end for at in framed):
            continue
        if end == size and data[size - 3:] == bytes(3):
            #? zero bytes appended - a sum that has come to zero stays there through them. The audio ends somewhere
            #? in the run (its last two bytes may be the frame's own CRC-16), so at least all but two are extra.
            run = _zero_run(data)
            if run <= _silent(info):
                #? (review) a silent last frame ends in its own run of zeros - every channel's CONSTANT subframe of 0,
                #? then a CRC-16 of 0x0000: no sum can tell that from zeros appended, and doubt never refuses. (Only a
                #? CONSTANT subframe's header byte is 0x00, so no other frame is zeros for longer than this.)
                return Verdict(UNCHECKED, f"it ends in {run} zero bytes, which a silent last frame may end in itself")
            return Verdict(STALE_TAIL, f"{run} zero bytes at the end of the file", extra=run - 2)
        return Verdict(OK, "" if end == size else "a tag follows the audio")
    if not zeros:
        if size - pos <= reach + HEADER_MAX:
            return Verdict(CUT_SHORT, "the file ends inside the last frame")
        return Verdict(DAMAGED_INSIDE, "the last frame fails its checksum")
    #? The last frame checks out before the end of the file, but which zero is its end? A chance zero inside a frame
    #? is one byte in 65,536 - one frame in six or so of CD audio, most of a hi-res one's - so a file cut short in
    #? its last frame has them too. What says the bytes after a zero are EXTRA rather than the frame's own: a frame
    #? header there (a stale copy of earlier frames - a header by chance in audio is about one in 2^40 bytes) or the
    #? copy loop's fingerprint, either exact. Without either, the frame's expected length decides: a file ending
    #? before its last frame could have is cut short.
    copied = [at for at in zeros if at >= COPY_BUFFER and size - at < COPY_BUFFER
              and data[at:] == data[at - COPY_BUFFER:at - COPY_BUFFER + size - at]]
    headers = [at for at in _syncs(data, zeros[0], size) if _header_at(data, at, info)]
    if copied or framed:
        cut = (copied or framed)[0]
        return Verdict(STALE_TAIL, f"{size - cut} bytes after the end of the audio", extra=size - cut)
    if not headers and expected and size - pos < expected:
        return Verdict(CUT_SHORT, "the file ends inside the last frame")
    end = max([at for at in zeros if not headers or at <= headers[0]])
    span = f"{size - end}" if end == zeros[0] else f"{size - end} to {size - zeros[0]}"
    return Verdict(STALE_TAIL, f"{span} bytes after the end of the audio", extra=size - end)


def _silent(info) -> int:
    """
    The most zero bytes a frame of digital silence can end in (review): each channel's CONSTANT subframe - its
    header byte, 0x00, and the one sample, 0, a bit wider in a stereo side channel - then its CRC-16, 0x0000 when it
    comes to that. Eight for 16-bit stereo (channels x (1 + bytes per sample) + 2); a little more
    here, for the side channel's extra bit and the padding to a byte, since a refusal must be sure.
    """
    return (info.channels * (8 + info.bits_per_sample + 1) + 7) // 8 + 2


def _zero_run(data) -> int:
    """How many zero bytes `data` ends in - read back from the end a stretch at a time, never the whole file."""
    size, run = len(data), 0
    while run < size:
        stretch = data[max(0, size - run - READ_WINDOW):size - run]
        kept = len(stretch.rstrip(b"\0"))
        run += len(stretch) - kept
        if kept:
            break
    return run


def _tag_ends(data, start: int) -> list[int]:
    """
    Where the audio could end, last first: the end of the file, then before each tag found behind it - stripped
    from the end one at a time, again and again (TAGS_BEHIND at most), each the end of what is left: ID3v1 (with
    "TAG+" before it), APEv2 (its footer last, its header when it says it has one), ID3v2 with a "3DI" footer.
    Each is only a candidate, as in flac_mp4's _audio_ends: the last frame's CRC-16 decides, so a frame whose last
    bytes happen to spell "TAG" is not cut short by it. Nothing is taken from before `start`, the last frame.
    """
    end = len(data)
    ends = [end]
    for _ in range(TAGS_BEHIND):
        size = _tag_before(data, start, end)
        if not size:
            break
        end -= size
        ends.append(end)
    return ends


def _tag_before(data, start: int, end: int) -> int:
    """The size of the tag ending at `end`, or 0 for none - one that would reach back to `start` included."""
    if end - 128 > start and data[end - 128:end - 125] == b"TAG":
        if end - 355 > start and data[end - 355:end - 351] == b"TAG+":
            return 355
        return 128
    if end - 32 > start and data[end - 32:end - 24] == b"APETAGEX":
        size, flags = struct.unpack("<I4xI", data[end - 20:end - 8])
        ape = size + (32 if flags & 0x80000000 else 0)
        return ape if 32 <= ape < end - start else 0
    if end - 20 > start and data[end - 10:end - 7] == b"3DI":
        sizes = data[end - 4:end]
        if any(b & 0x80 for b in sizes):
            return 0
        whole = 20 + ((sizes[0] << 21) | (sizes[1] << 14) | (sizes[2] << 7) | sizes[3])
        if whole < end - start and data[end - whole:end - whole + 3] == b"ID3":
            return whole
    return 0


def _header_at(data, at: int, info) -> bool:
    """Whether a frame header of this stream, right in every particular, begins at `at` (any number)."""
    return data[at:at + 2] in _SYNCS and _frame_header(data, at, info) is not None


def _syncs(data, start: int, end: int):
    """Every place from `start` to `end` where either sync code begins."""
    for sync in _SYNCS:
        at = data.find(sync, start, end)
        while at >= 0:
            yield at
            at = data.find(sync, at + 1, end)


#? (review) how much of a file the check holds in memory at once (_Reader): a window, slid along as the walk goes -
#? bar one stretch longer than it that is asked for whole (a frame summed, a frame's reach)
READ_WINDOW = 4 << 20
#? ...and how much before what is asked for each window keeps, for the walk's looks back (the frame it is in, the
#? copy loop's 6,144 bytes)
READ_BEHIND = 256 << 10


class _Reader:
    """
    (Damaged downloads, review) A file as check() reads it - bytes' len, indexing, slicing, find and startswith,
    which is all the walk and flac_mp4's parsers ask of it - read a window at a time from an open file, so an album
    of 24/192 FLACs is never in memory whole. A file that comes up shorter than it was when opened raises OSError
    (check_file: UNCHECKED).
    """

    def __init__(self, handle, size: int):
        self.handle, self.size = handle, size
        self.low, self.window = 0, b""

    def __len__(self) -> int:
        return self.size

    def _hold(self, start: int, end: int) -> None:
        """Have data[start:end] in the window (both already within the file)."""
        if start >= self.low and end <= self.low + len(self.window):
            return
        low = max(0, start - READ_BEHIND)
        high = min(self.size, max(end, low + READ_WINDOW))
        self.window = os.pread(self.handle.fileno(), high - low, low)
        self.low = low
        if len(self.window) < high - low:
            self.window = b""
            raise OSError("the file is shorter than it was when it was opened")

    def __getitem__(self, key):
        if isinstance(key, slice):
            start, stop, step = key.indices(self.size)
            if step != 1:
                raise ValueError("only whole stretches are read")
            if stop <= start:
                return b""
            self._hold(start, stop)
            return self.window[start - self.low:stop - self.low]
        if key < 0:
            key += self.size
        if not 0 <= key < self.size:
            raise IndexError("past the end of the file")
        self._hold(key, key + 1)
        return self.window[key - self.low]

    def startswith(self, prefix: bytes, start: int = 0) -> bool:
        return self[start:start + len(prefix)] == prefix

    def find(self, sub: bytes, start: int = 0, end: int | None = None) -> int:
        end = self.size if end is None else min(end, self.size)
        at = max(0, start)
        while at + len(sub) <= end:
            self._hold(at, min(end, at + len(sub)))
            reach = min(end, self.low + len(self.window))
            found = self.window.find(sub, at - self.low, reach - self.low)
            if found >= 0:
                return found + self.low
            if reach >= end:
                return -1
            #? the next window from where a match could still start
            at = reach - len(sub) + 1
        return -1


def check_file(path: Path | str) -> Verdict:
    """check() of the file at `path`, read a window at a time (_Reader) - UNCHECKED, read nowhere, for one over
    flac_mp4's 1 GiB, or one that can't be read or shrinks while it is (filing it would fail the same way, and say
    so)."""
    path = Path(path)
    try:
        with path.open("rb") as handle:
            size = os.fstat(handle.fileno()).st_size
            if size > MAX_INPUT_BYTES:
                return Verdict(UNCHECKED, f"larger than {MAX_INPUT_BYTES >> 20} MiB")
            return check(_Reader(handle, size))
    except OSError as e:
        return Verdict(UNCHECKED, f"couldn't be read: {e}")


# --- the words ----------------------------------------------------------------------------------------------

def damage_reason(kinds: list[str], songs: int) -> str:
    """
    Why a download was refused, in a listener's words - what goes in the brackets of "The copy from glassbeads was
    damaged (...)": "extra data after the end of 3 of 11 songs", "1 of 11 songs is cut short", "2 of 11 songs are
    damaged inside", the kinds found joined in that order. `kinds` has one entry per damaged song; `songs` is how
    many songs the download held.
    """
    songs = max(songs, len(kinds))
    parts = []
    for kind in DAMAGED:
        count = kinds.count(kind)
        if not count:
            continue
        if kind == STALE_TAIL:
            parts.append(f"extra data after the end of {count} of {songs} {_songs(songs)}")
        else:
            verb = "is" if count == 1 else "are"
            state = "cut short" if kind == CUT_SHORT else "damaged inside"
            parts.append(f"{count} of {songs} {_songs(songs)} {verb} {state}")
    return "; ".join(parts)


def _songs(count: int) -> str:
    return "song" if count == 1 else "songs"
