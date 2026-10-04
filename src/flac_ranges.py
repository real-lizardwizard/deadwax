"""
A window of a song cut straight from its FLAC on Navidrome, a byte range at a time (2.0.0-player.23).

James, on the desktop visualizer's one documented cost: "yes, cut the windows straight from the
FLAC". The turntable's windows (src/flac_window.py), which the visualizer's silent copy uses too,
were always cut from an MP4 the player's cache keeps of the song - and a page that plays the FLAC as
it is (Chrome, Firefox or Edge with Gapless off) never has one made, so its first window of each song
had deadwax download the whole song again and keep its MP4 in the cache, against PLAYER_CACHE_MB,
pushing an iPhone's songs out. A cached MP4 is still used wherever one is held (src/player_cache.py);
otherwise the window is now read out of the FLAC itself:

  THE HEAD (read_head): 'fLaC', after any ID3v2 tags in front of it, then the metadata blocks to the
  one flagged last - STREAMINFO, which RFC 9639 puts first, and a SEEKTABLE when there is one, read;
  anything else skipped by its length, a cover of many megabytes included, by reading on from past
  it - never downloaded. The first frame starts where the last block ends, and its header says
  whether the stream numbers its frames (fixed blocks) or their first samples (variable). Then the
  file's last few hundred bytes, which say what tags follow the audio (ID3v1, APEv2 -
  flac_mp4._audio_ends): a tag longer than a frame - an APEv2 tag holding a cover - is never read,
  and a window's reads stop where the audio can end (Head.end). A STREAMINFO that doesn't know the
  song's length (0, "not known") has it found there too: the last frame, checked as a whole file's
  last frame is.

  FINDING THE WINDOW (cut): a frame at or before the window's first sample, closed in on from the
  seek table's points around it, the frames earlier windows of the song found (`points`), or an
  estimate from the song's size and length - by small reads (probes), each of which syncs to the
  first REAL frame in it: a header right in every particular (flac_mp4._frame_header - the sync
  code, the reserved bits, the CRC-8, a block size and rate this STREAMINFO allows), a number inside
  the song, the frames after it followed by flac_mp4._split_frames, and its own CRC-16 summing to
  zero. The same two bytes as a sync code turn up inside audio every few tens of kilobytes, and by
  chance none of them is ever taken for a frame (a file BUILT to fool it is another matter - see
  cut()). Then ONE read from just before that frame to past the window's end (more when the
  estimate fell short, each sized by what the frames read so far took), the frames split out of it
  by _split_frames exactly as out of a whole file, and the window built by
  flac_window.flac_of_frames under exactly cut_window's rules - the frame `at` falls in, then frames
  to `at + seconds` within the budget. deadwax's MP4s carry the FLAC's frames untouched and a window
  renumbers its own under a STREAMINFO of its own, so the window is BYTE FOR BYTE the one cut from
  the plain MP4 of the same file (tests/test_flac_ranges.py holds them equal).

Bounded: a head takes at most HEAD_READS reads and a window WINDOW_READS, and a window's reads add up
to about its own size and what finding it took - never the song (read_limit()). Anything this can't
read with certainty - a head that isn't a FLAC's, frames that don't hold together, more reads than
that - raises CannotCut, and the caller cuts the window from an MP4 instead, as before; a window
asked for at or past the end raises PastTheEnd, as cut_window does.

Pure, like flac_window.py: nothing here does any I/O. Each step is a generator that YIELDS the
(offset, length) of the file it needs next and is sent those bytes back; run() drives one with a
function over bytes in memory, and src/player_cache.py drives it with ranged reads of Navidrome.
"""

import struct
from bisect import bisect_left, bisect_right
from dataclasses import dataclass
from typing import Callable, Generator, TypeVar

from src.flac_mp4 import (HEADER_MAX, TRAILER_MAX, FlacFrames, StreamInfo, Unsupported, _audio_ends, _crc16,
                          _frame_header, _parse_streaminfo, _reach, _split_frames)
from src.flac_window import CannotCut, PastTheEnd, Window, flac_of_frames

T = TypeVar("T")

#? A step: it yields the (offset, length) of the file it wants, is sent exactly those bytes, and
#? returns its answer.
Steps = Generator[tuple[int, int], bytes, T]

#? A song's place: (where a frame of it starts in the file, the song's sample that frame starts at).
Place = tuple[int, int]

#? What the head is read in: the metadata of most files, and the first frame's header after it, in
#? one read. A block too long for it that isn't needed - a cover - is skipped, the next read starting
#? past it.
HEAD_CHUNK = 64 << 10

#? The most reads a song's head takes: the first, one for each metadata block that has to be read on
#? into or skipped - a booklet of scans embedded as pictures is a read each - and the end of the file,
#? with one more there for a STREAMINFO that doesn't know the song's length behind a tag longer than
#? a frame. A head is read once a version and kept (src/player_cache.py), so plenty costs little; past
#? it the file is laid out as this doesn't read, and its windows are cut from an MP4.
HEAD_READS = 32

#? The most reads one window takes, its song's head aside: up to PROBES to find where it starts, then
#? the read of its frames, and up to three more when the estimate of how far they reach fell short.
#? Most windows take one or two: a seek table or an earlier window's frames leave nothing to find,
#? and a song whose bytes follow its samples is found in a probe or two. The rest is for a long song
#? with no seek table whose bytes don't follow its samples at all - quiet and loud stretches, a hidden
#? track after minutes of silence - where the probes halve what is left (_locate), each a few tens
#? of kilobytes, where a read from too far back would be megabytes.
PROBES = 10
WINDOW_READS = PROBES + 4

#? What a probe reads beyond the two frames' reach it needs - so a frame begins in it, and the next
#? frame's header after it shows: room for a false sync or two in front of the first real header.
PROBE_SLACK = 4096

#? The largest seek table read. A table past it - an hour of audio has 360 points at libFLAC's one
#? every 10 s, 6.5 KB - is skipped like any other block, and the song's windows found by estimate.
SEEKTABLE_MAX = 64 << 10

#? How many of the frames earlier windows found are kept per song, to start later windows from.
POINTS_KEPT = 1024

_STREAMINFO, _SEEKTABLE, _INVALID = 0, 3, 127
#? a stream's sync code: the fixed-block one and the variable-block one
_SYNC = {True: b"\xff\xf8", False: b"\xff\xf9"}


@dataclass(frozen=True)
class Head:
    """What a song's FLAC says before its audio, and where that audio is."""

    size: int
    info: StreamInfo
    #? where the first frame starts: where the last metadata block ends
    first: int
    #? whether the stream numbers its frames (fixed blocks: frame n starts at sample n * block) or
    #? their first samples (variable blocks), and the first frame's block size
    fixed: bool
    block: int
    #? the song's length in samples: STREAMINFO's, or found at the end of the file when it says 0
    total: int
    #? how far into the file a window reads: the latest place the audio can end (flac_mp4._audio_ends)
    #? within a frame's reach of the earliest - the end of the file, unless a tag longer than that
    #? follows the audio (an APEv2 tag holding a cover), whose bytes are then never read
    end: int
    #? the file's last bytes - TRAILER_MAX of them, or all of them from where its audio starts - which
    #? say what tags follow the audio, and where in the file they begin
    tail: bytes
    tail_at: int
    #? the seek table's points as (sample, where its frame starts in the file), placeholders and any
    #? that don't run forward left out
    points: tuple[tuple[int, int], ...] = ()


def read_limit(max_bytes: int, reach: int) -> int:
    """
    The most of the file one window's reads may add up to: twice its budget, every probe, and a few
    frames' reach besides. A window takes about its own size and the lead it is read from (_lead);
    this is the bound past which something is wrong - an estimate that never closes in, a seek table
    pointing elsewhere - and the window is cut from an MP4 instead, rather than the song read.
    """
    return 2 * max_bytes + PROBES * _probe_length(reach) + 16 * reach + (1 << 20)


def _probe_length(reach: int) -> int:
    return 2 * reach + HEADER_MAX + PROBE_SLACK


class _Reads:
    """What one step may still ask of the file: so many reads, and so many bytes."""

    def __init__(self, size: int, reads: int, limit: int | None = None):
        self.size, self.left, self.limit, self.taken = size, reads, limit, 0

    def read(self, offset: int, length: int) -> Steps[bytes]:
        length = min(length, self.size - offset)
        if offset < 0 or length <= 0:
            raise CannotCut("a read outside the file")
        if self.left <= 0:
            raise CannotCut("it would take more reads than a window may")
        if self.limit is not None and self.taken + length > self.limit:
            raise CannotCut("it would read more of the file than a window may")
        self.left -= 1
        self.taken += length
        data = yield (offset, length)
        if len(data) != length:
            raise CannotCut(f"{len(data)} bytes came back of the {length} asked for")
        return bytes(data)


class _Stretch:
    """The run of the file read last, carried on into by a read when what is wanted runs past its
    end, or left for a run of its own when what is wanted is elsewhere - past a cover, say."""

    def __init__(self, reads: _Reads, chunk: int):
        self.reads, self.chunk = reads, chunk
        self.start, self.data = 0, b""

    def get(self, offset: int, length: int) -> Steps[bytes]:
        """The file's bytes from `offset`, `length` of them - fewer only at its end."""
        end = min(offset + length, self.reads.size)
        here = self.start + len(self.data)
        if not (self.start <= offset and end <= here):
            if self.data and self.start <= offset <= here:
                self.data += yield from self.reads.read(here, max(end - here, self.chunk))
            else:
                self.start = offset
                self.data = yield from self.reads.read(offset, max(end - offset, self.chunk))
        return self.data[offset - self.start:end - self.start]


def read_head(size: int) -> Steps[Head]:
    """
    The head of a FLAC file `size` bytes long (see the module's docstring). Raises CannotCut for one
    that isn't laid out as a FLAC file is: no 'fLaC', a STREAMINFO missing, malformed or not first, a
    block of the invalid type, blocks that run past the end of the file, no frame where they end.
    """
    reads = _Reads(size, HEAD_READS)
    stretch = _Stretch(reads, HEAD_CHUNK)
    pos = 0
    #? ID3v2 tags in front, as flac_mp4's own reading allows - more than one is legal, if rare
    for _ in range(8):
        if size - pos < 10:
            break
        tag = yield from stretch.get(pos, 10)
        if not tag.startswith(b"ID3"):
            break
        if any(byte & 0x80 for byte in tag[6:10]):
            raise CannotCut("an ID3v2 tag in front that isn't a valid one")
        footer = 10 if tag[5] & 0x10 else 0
        pos += 10 + ((tag[6] << 21) | (tag[7] << 14) | (tag[8] << 7) | tag[9]) + footer
    if size - pos < 4 or (yield from stretch.get(pos, 4)) != b"fLaC":
        raise CannotCut("no 'fLaC' marker at the start of the file")
    pos += 4
    info, table = None, b""
    while True:
        if pos + 4 > size:
            raise CannotCut("the metadata runs past the end of the file")
        header = yield from stretch.get(pos, 4)
        kind, last, length = header[0] & 0x7F, header[0] & 0x80, int.from_bytes(header[1:4], "big")
        if pos + 4 + length > size:
            raise CannotCut("the metadata runs past the end of the file")
        if info is None:
            if kind != _STREAMINFO or length != 34:
                raise CannotCut("the first metadata block isn't STREAMINFO")
            try:
                info = _parse_streaminfo((yield from stretch.get(pos + 4, 34)))
            except Unsupported as e:
                raise CannotCut(f"its STREAMINFO isn't valid ({e})") from e
        elif kind == _INVALID:
            raise CannotCut("a metadata block of the invalid type 127")
        elif kind == _SEEKTABLE and length <= SEEKTABLE_MAX:
            table = yield from stretch.get(pos + 4, length)
        pos += 4 + length
        if last:
            break
    first = pos
    if first >= size:
        raise CannotCut("no audio frames")
    lead = yield from stretch.get(first, HEADER_MAX)
    if lead[:1] != b"\xff" or lead[1:2] not in (b"\xf8", b"\xf9"):
        raise CannotCut("no audio frame where the metadata ends")
    got = _frame_header(lead, 0, info)
    if got is None or got[0] != 0:
        raise CannotCut("the first audio frame's header isn't valid")
    fixed, block = lead[1] == 0xF8, got[1]
    reach, total = _reach(info), info.total_samples
    #? The end of the file, for what tags follow the audio - and for a STREAMINFO that doesn't know the
    #? song's length, the last frames' worth before them, in the same read.
    near = max(first, size - (TRAILER_MAX if total else _probe_length(reach) + TRAILER_MAX))
    ending = yield from stretch.get(near, size - near)
    tail_at = max(near, size - TRAILER_MAX)
    tail = ending[tail_at - near:]
    ends = _audio_ends(b"", first, (tail, tail_at))
    end = max(place for place in ends if place - min(ends) <= reach)
    if not total:
        total = yield from _length_at_the_end(first, info, fixed, block, reach, reads, (near, ending),
                                              (tail, tail_at), end)
    return Head(size=size, info=info, first=first, fixed=fixed, block=block, total=total, end=end,
                tail=tail, tail_at=tail_at, points=_seek_points(table, first, end, total))


def _seek_points(table: bytes, first: int, end: int, total: int) -> tuple[tuple[int, int], ...]:
    """A SEEKTABLE's points, as (sample, where in the file its frame starts): placeholders, points
    outside the song or its audio, and any that don't run forward from the one before left out."""
    points, last = [], (-1, -1)
    for sample, offset, _ in struct.iter_unpack(">QQH", table[:len(table) - len(table) % 18]):
        at = first + offset
        #? a placeholder's sample is all ones - past the end of every song
        if sample >= total or at >= end:
            continue
        if sample > last[0] and at > last[1]:
            last = (sample, at)
            points.append(last)
    return tuple(points)


def _length_at_the_end(first: int, info: StreamInfo, fixed: bool, block: int, reach: int, reads: _Reads,
                       held: tuple[int, bytes], tail: tuple[bytes, int], end: int) -> Steps[int]:
    """The song's length in samples, for a STREAMINFO that doesn't say: its last frame's first sample
    and block size, from the frames before where its audio can end (Head.end) - read with the end of
    the file when they were in it (`held`: where that read began, and its bytes) - the last frame
    checked as a whole file's is."""
    begin = max(first, end - _probe_length(reach))
    near, ending = held
    if begin >= near:
        data = ending[begin - near:end - near]
    else:
        data = yield from reads.read(begin, end - begin)
    found = _first_frame(data, info, fixed, block, None, True, (tail[0], tail[1] - begin))
    if found is None:
        raise CannotCut("STREAMINFO doesn't say how long it is, and where its audio ends couldn't be found")
    _, sample, frames = found
    return sample + sum(frames.block_sizes)


def _first_frame(data: bytes, info: StreamInfo, fixed: bool, block: int, total: int | None,
                 to_the_end: bool, tail: tuple[bytes, int] | None = None,
                 before: int | None = None) -> tuple[int, int, FlacFrames] | None:
    """
    The first REAL frame in `data` - where it starts, its first sample, and the frames from it that
    _split_frames found - or None; with `before`, one starting no further in than that. A candidate
    header has to be right in every particular (_frame_header), carry a number inside the song (and,
    in a fixed-block stream, the stream's block size unless it ends the song), and begin frames
    _split_frames can follow, the first of which sums to zero with its own CRC-16: a false sync passes
    the header's checks now and then, and that sum only once in 65,536 times on top of it. (A copy of a
    real header planted in the audio, with two bytes set so the sum comes out, passes every time -
    which is why cut() never takes a window's frames on the word of this one alone.) `tail` is
    _split_frames' own, for `data` that runs to where the audio can end.
    """
    sync = _SYNC[fixed]
    at = data.find(sync)
    while at >= 0 and (before is None or at <= before):
        got = _frame_header(data, at, info)
        if got is not None:
            number, size, _ = got
            sample = number * block if fixed else number
            inside = total is None or sample < total
            whole = not fixed or size == block or total is None or sample + size == total
            if inside and whole:
                try:
                    frames = _split_frames(data, at, info, number, to_the_end, tail)
                except Unsupported:
                    frames = None
                if frames is not None and frames.starts and _checks_out(data, frames):
                    return at, sample, frames
        at = data.find(sync, at + 1)
    return None


def _checks_out(data: bytes, frames: FlacFrames) -> bool:
    """The first of `frames` sums to zero with its own CRC-16, from its header to the next frame's."""
    end = frames.starts[1] if len(frames.starts) > 1 else frames.end
    return _crc16(data[frames.starts[0]:end]) == 0


def _lead(head: Head, start: int, end: int, max_bytes: int, reach: int) -> int:
    """How far before the frame a window starts in its read may begin without another probe: an
    eighth of the window as the song's average rate would have it, or eight frames' reach."""
    span = (min(end, head.total) - start) * (head.end - head.first) // head.total
    return max(8 * reach, min(span, max_bytes) // 8)


def _locate(head: Head, start: int, lead: int, points: tuple[tuple[int, int], ...], reads: _Reads,
            reach: int) -> Steps[tuple[Place, Place]]:
    """
    Two places around the song's sample `start`: `low`, a frame starting at or before it - the first
    frame, a seek point, a frame an earlier window found, or one a probe found - and `high`, a place
    past it (where the audio ends, or a frame or point after it). Probes close in on it, each aimed a
    little before where the samples between the two would put it, until that is within `lead` of
    `low` - or PROBES have been spent, and the read starts from the nearest `low` found.

    A song's bytes don't follow its samples evenly, though - silence takes next to nothing, a loud
    passage twice the average - and where they don't, the samples' guess lands on the same side again
    and again, closing in a little at a time: four probes into the noise half of a song that is half
    silence all landed past the moment, and the read began at the song's start. So once the same end
    has moved twice running, the next probe goes halfway between the two instead - which halves the
    stretch whatever the song does - and the guesses go back to the samples' once the other end moves.
    A long song with no seek table whose loudness swings - 45 minutes of quiet and loud, a hidden
    track after minutes of silence - can take most of PROBES halving it.
    """
    low, high = (head.first, 0), (head.end, head.total)
    for sample, offset in head.points + points:
        if sample <= start:
            if offset > low[0]:
                low = (offset, sample)
        elif offset < high[0]:
            high = (offset, sample)
    moved, streak = None, 0
    for _ in range(PROBES):
        if not low[0] < high[0]:
            raise CannotCut("its seek points don't agree with its frames")
        if streak >= 2:
            guess = (low[0] + high[0]) // 2
        else:
            guess = low[0] + (start - low[1]) * (high[0] - low[0]) // (high[1] - low[1])
        if guess - low[0] <= lead:
            break
        at = max(low[0] + 1, guess - lead // 2)
        found = yield from _probe(head, at, reads, reach)
        side = "low" if found is not None and found[1] <= start else "high"
        if found is None:
            #? no frame starts from there to the end: the last one starts before it
            high = (at, high[1])
        elif side == "low":
            low = found
        else:
            #? no frame starts between `at` and the one found, so the one `start` is in begins before it
            high = (at, found[1])
        streak = streak + 1 if side == moved else 1
        moved = side
    if not low[0] < high[0]:
        raise CannotCut("its seek points don't agree with its frames")
    return low, high


def _probe(head: Head, at: int, reads: _Reads, reach: int) -> Steps[Place | None]:
    """The first real frame starting at or after `at`: (where, its first sample) - or None when none
    does before the audio ends."""
    length = min(head.end - at, _probe_length(reach))
    data = yield from reads.read(at, length)
    to_the_end = at + length >= head.end
    found = _first_frame(data, head.info, head.fixed, head.block, head.total, to_the_end,
                         (head.tail, head.tail_at - at) if to_the_end else None)
    if found is None:
        if not to_the_end:
            #? a frame begins within every frame's reach of audio
            raise CannotCut("no frame where one has to begin")
        return None
    return at + found[0], found[1]


def _pace(frames: FlacFrames, firsts: list[int], reached: int, since: int) -> float:
    """
    The bytes a sample the frames from `since` on took - or what the later half of them by their bytes
    took, when that is more: what a read on is sized by. Their average alone lags behind a song that
    gets louder - a hidden track after minutes of silence - and sized by it, each read reached less
    far than the one before, until the reads ran out.
    """
    starts = frames.starts
    pace = (frames.end - starts[since]) / (reached - firsts[since])
    later = bisect_left(starts, (starts[since] + frames.end) // 2, since)
    if later < len(starts):
        pace = max(pace, (frames.end - starts[later]) / (reached - firsts[later]))
    return pace


def cut(head: Head, at: float, seconds: float, max_bytes: int,
        points: tuple[tuple[int, int], ...] = ()) -> Steps[tuple[Window, tuple[tuple[int, int], ...]]]:
    """
    The stretch of the song from `at` seconds for `seconds`, as a FLAC file of its own - exactly
    flac_window.cut_window's window of the plain MP4 of the same file: from the frame `at` falls in,
    to `at + seconds` or the song's end, never more than `max_bytes` of audio bar that first frame -
    and the frames it found on the way, as (sample, where it starts), at about a lead apart, for the
    song's next windows to start from (`points`). PastTheEnd for an `at` at or past the end of the
    song; CannotCut for anything this can't read with certainty (see the module's docstring).

    The read starts a frame's reach and a header before the frame `low` (bar the song's first frame,
    where the metadata ends): the frame before it begins in there, the frames are split from THAT
    one, and `low` has to be one _split_frames found after it, at the sample they make it - or
    CannotCut (a seek point that isn't on a frame, or names another sample, earlier or later), judged
    as soon as the frames read run past `low`, before a window is looked for in them. So no frame of a
    window is ever taken on its own header and CRC-16 alone: each is one the whole file's rules found
    after another, where a copy of its header planted in the audio - two bytes set so its CRC-16 comes
    out - is found out by the number already given and the sums, as in a whole file. What that can't
    see is a file BUILT with copies of several headers in a row in front of the frame read from, the
    first of them taken for the frame before: read from frame 0, a whole file finds those out too, and
    a stretch can't. Like the MP4 path's own (flac_mp4._last_frame_end), it takes a file made to do it.
    """
    info, rate = head.info, head.info.sample_rate
    start = max(0, int(at * rate))
    if start >= head.total:
        raise PastTheEnd(f"the song is {head.total / rate:.3f} s long")
    end = start + max(1, int(seconds * rate))
    reach = _reach(info)
    reads = _Reads(head.end, WINDOW_READS, read_limit(max_bytes, reach))
    lead = _lead(head, start, end, max_bytes, reach)
    low, high = yield from _locate(head, start, lead, points, reads, reach)

    back = 0 if low[0] == head.first else min(low[0] - head.first, reach + HEADER_MAX)
    offset = low[0] - back
    #? How far to read, in bytes per sample: between the two places to reach `start`, and for the
    #? window the more of that and the song's average, an eighth over - then, once frames are read,
    #? what they really took (_pace). Too little costs another read; too much, bytes - never past the
    #? budget.
    average = (head.end - head.first) / head.total
    between = (high[0] - low[0]) / (high[1] - low[1])
    stop = min(end, head.total)
    more = back + int((start - low[1]) * between)
    more += min(int((stop - start) * max(between, average) * 1.125), max_bytes + reach)
    data, anchor = b"", None
    while True:
        data += yield from reads.read(offset + len(data), max(more + reach + HEADER_MAX, _probe_length(reach)))
        whole = offset + len(data) >= head.end
        tail = (head.tail, head.tail_at - offset) if whole else None
        try:
            if anchor is not None:
                frames = _split_frames(data, anchor[0], info, anchor[2], whole, tail)
            elif not back:
                frames = _split_frames(data, 0, info, 0, whole, tail)
                anchor = (0, 0, 0)
            else:
                #? the frame the read's frames are taken from: the first real one in its first `back`
                #? bytes - the one before `low`, as a rule
                found = _first_frame(data, info, head.fixed, head.block, head.total, whole, tail, before=back)
                if found is None:
                    if whole:
                        raise CannotCut("no frame where one has to begin")
                    more = 0
                    continue
                place, sample, frames = found
                anchor = (place, sample, sample // head.block if head.fixed else sample)
        except Unsupported as e:
            raise CannotCut(f"its frames don't hold together there ({e})") from e
        if not frames.starts:
            more = 0
            continue
        #? The frame the frames are split from is the song's first - taken on its header, where the
        #? metadata ends, exactly as a whole file takes it - or one _first_frame found and checked by its
        #? CRC-16. Nothing more is asked of it: a window never starts on it unless it is the first.
        blocks = frames.block_sizes
        if head.fixed and any(size != head.block for size in (blocks[:-1] if whole else blocks)):
            raise CannotCut("a fixed-block-size stream whose frames change size")
        firsts = [anchor[1]]
        for size in blocks[:-1]:
            firsts.append(firsts[-1] + size)
        reached = firsts[-1] + blocks[-1]
        if back:
            #? `low` has to be one of the frames found after the first, at the sample they make it -
            #? judged from the first read on, before anything else is made of the frames (that read runs
            #? a frame's reach and a header past `low`, so the frame at `low`, or the one it falls in, is
            #? among the certain ones). A seek point naming a sample EARLIER than its frame's puts the
            #? frame read from past the window's start: judged only after the window was looked for,
            #? that ended in a ValueError out of _pace - a 500 where the MP4 path cut the window
            #? (2.0.0-player.23's second review).
            index = bisect_left(frames.starts, back)
            if not (0 < index < len(frames.starts) and frames.starts[index] == back and firsts[index] == low[1]):
                raise CannotCut("where its window was read from isn't a frame of this stream at the sample said - "
                                "a seek point that isn't on one")
        if whole and reached != head.total:
            raise CannotCut(f"its frames end at sample {reached} where its length says {head.total}")
        sizes = [b - a for a, b in zip(frames.starts, frames.starts[1:] + (frames.end,))]
        if reached <= start:
            #? not there yet: on to the window at the pace the frames read took, and the window
            pace = _pace(frames, firsts, reached, 0)
            more = int((start - reached) * pace) + min(int((stop - start) * max(between, average, pace) * 1.125),
                                                       max_bytes + reach)
            continue
        lo = bisect_right(firsts, start) - 1
        hi, held = lo, 0
        while hi < len(firsts) and firsts[hi] < end and (hi == lo or held + sizes[hi] <= max_bytes):
            held += sizes[hi]
            hi += 1
        if hi == len(firsts) and not whole and reached < end and held < max_bytes:
            #? the next frame might still fit: read on as far as the rest of the window would reach, at
            #? the pace its frames so far took
            more = min(int((stop - reached) * _pace(frames, firsts, reached, lo) * 1.125), max_bytes - held)
            continue
        break

    picked = [(data[frames.starts[i]:frames.starts[i] + sizes[i]], blocks[i]) for i in range(lo, hi)]
    window = flac_of_frames(info, picked, firsts[lo], song_samples=head.total)
    #? the frames after the first - each one the whole file's rules found after another - to start the
    #? song's next windows from
    found, mark = [], None
    for i in range(1, len(frames.starts)):
        if mark is None or offset + frames.starts[i] - mark >= lead:
            mark = offset + frames.starts[i]
            found.append((firsts[i], mark))
    return window, tuple(found)


def keep_points(held: tuple[tuple[int, int], ...], found: tuple[tuple[int, int], ...]) -> tuple[tuple[int, int], ...]:
    """The frames a song's windows found, merged in order and kept to POINTS_KEPT - every other one
    let go when there are more, so they stay spread over the song."""
    points = tuple(sorted(set(held) | set(found)))
    while len(points) > POINTS_KEPT:
        points = points[::2]
    return points


def run(steps: Steps[T], read: Callable[[int, int], bytes]) -> T:
    """A step driven to its answer, each read it asks for answered by `read(offset, length)`."""
    try:
        wanted = next(steps)
        while True:
            wanted = steps.send(read(*wanted))
    except StopIteration as done:
        return done.value


def advance(steps: Steps[T], data: bytes | None) -> tuple[bool, object]:
    """One move of a step - started with None, then sent each read's bytes: (True, its answer) once
    it has one, else (False, the next (offset, length) it asks for). For a driver running the step in
    a worker thread, which StopIteration can't be carried out of (an asyncio future refuses it)."""
    try:
        return False, (next(steps) if data is None else steps.send(data))
    except StopIteration as done:
        return True, done.value
