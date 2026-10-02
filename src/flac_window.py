"""
A stretch of a song as a FLAC file of its own, cut from deadwax's own MP4s - the turntable's sound
(2.0.0-player.14).

The phone's turntable plays the record's own sound while a hand turns it, while a flick coasts and
while a pause winds it down: a stretch of the song round the playhead, decoded, and read by an
AudioWorklet at any speed, backwards too (ui/src/lib/deckVoice.ts). The browser decodes it with
decodeAudioData, which takes a whole file and never a piece of one - so deadwax takes the frames
that cover the stretch out of the MP4 its cache already keeps of the song (src/player_cache.py) and
makes them a FLAC of their own:

- 'fLaC', then STREAMINFO as the only metadata block, rewritten for the window: its total samples,
  its own frames' smallest and largest sizes, and the MD5 zeroed (which FLAC reads as "not known").
  The block sizes, rate, channels and depth stay the song's.
- The frames, their audio untouched and RENUMBERED from 0 - frame numbers in a fixed-block stream,
  sample numbers in a variable one - with each header's CRC-8 and each frame's CRC-16 made again.
  So a decoder that reads the numbers sees an ordinary file rather than the middle of one: deadwax's
  own find_frames() refuses a first frame that isn't 0, and whether Apple's decoder (decodeAudioData
  on an iPhone) would mind the song's own numbers isn't known, so they aren't left to it.

The CRC-16 isn't summed again over each frame. FLAC's starts at zero with nothing reflected, so it
is linear: the sum of a header followed by the rest is the header's sum carried through as many
zero bytes as the rest has, added to the rest's own. A new header therefore changes the frame's sum
by an amount that depends only on the two headers and the length after them (`_crc16_after`), a
few dozen operations a frame - where summing every byte again in Python would take a quarter of a
second for half a minute of CD audio.

The MP4s are deadwax's own, so they are read as deadwax lays them out (flac_mp4.mp4_layout and
fmp4_layout): the plain MP4's sample tables give every frame; the fragmented one's index (sidx)
gives every fragment of about a second, and a fragment's own table its frames. Anything else is
refused (CannotCut) rather than guessed at.

Pure: bytes in, bytes out - the file is read through a function it is handed.
"""

import struct
from bisect import bisect_right
from dataclasses import dataclass
from typing import Callable

from src.flac_mp4 import _NUMBER_TAILS, StreamInfo, _crc8, _crc16, _frame_header, _parse_streaminfo


class CannotCut(ValueError):
    """The window can't be cut from this file - it isn't laid out as deadwax lays them out."""


class PastTheEnd(CannotCut):
    """The window asked for starts at or after the end of the song."""


#? the CRC-16's polynomial with its top term: x^16 + x^15 + x^2 + 1
_POLY16 = 0x18005

#? the largest number FLAC's coding of a frame or sample number can carry: 36 bits
_NUMBER_LIMIT = 1 << 36
#? the least number each count of continuation bytes may carry, and one past the most: a number
#? below the next one's least is coded with this many
_NUMBER_LIMITS = (1 << 11, 1 << 16, 1 << 21, 1 << 26, 1 << 31, 1 << 36)


def coded_number(number: int) -> bytes:
    """A frame or sample number as a FLAC frame header codes it: UTF-8's scheme, stretched to 36
    bits, always the shortest way (RFC 9639, 9.1.5)."""
    if not 0 <= number < _NUMBER_LIMIT:
        raise CannotCut(f"{number} can't be a frame or sample number")
    if number < 0x80:
        return bytes((number,))
    for tail, limit in enumerate(_NUMBER_LIMITS, start=1):
        if number < limit:
            lead = ((0xFF << (7 - tail)) & 0xFF) | (number >> (6 * tail))
            rest = bytes(0x80 | ((number >> (6 * i)) & 0x3F) for i in range(tail - 1, -1, -1))
            return bytes((lead,)) + rest
    raise CannotCut(f"{number} can't be a frame or sample number")  # pragma: no cover - the limit above


def _mulmod(a: int, b: int) -> int:
    """a times b, as polynomials over GF(2), modulo the CRC-16's polynomial (both under 2^16)."""
    result = 0
    while b:
        if b & 1:
            result ^= a
        b >>= 1
        a <<= 1
        if a & 0x10000:
            a ^= _POLY16
    return result


def _shifts() -> tuple[int, ...]:
    """x^(8 * 2^k) mod the polynomial, for k from 0: one byte, two, four... far past any frame."""
    table = [0x100]
    for _ in range(47):
        table.append(_mulmod(table[-1], table[-1]))
    return tuple(table)


_SHIFTS = _shifts()


def _crc16_after(crc: int, length: int) -> int:
    """The CRC-16 a running sum of `crc` becomes once `length` zero bytes have gone through it -
    which, the CRC being linear, is what it adds to whatever follows."""
    k = 0
    while length:
        if length & 1:
            crc = _mulmod(crc, _SHIFTS[k])
        length >>= 1
        k += 1
    return crc


def _coded_length(lead: int) -> int:
    """How many bytes a coded number takes, from its first byte."""
    return 1 if lead < 0x80 else 1 + _NUMBER_TAILS[lead]


def renumber(frame: bytes, info: StreamInfo, number: int) -> bytes:
    """
    The frame with `number` in its header in place of the number it had - a frame number in a
    fixed-block stream, a sample number in a variable one - its header's CRC-8 made again, and its
    CRC-16 carried over to the new header (see the module's docstring). Its audio is untouched.
    Raises CannotCut for bytes that aren't a frame this stream's STREAMINFO allows.
    """
    read = _frame_header(frame, 0, info)
    if read is None or frame[:1] != b"\xff" or frame[1] & 0xFE != 0xF8:
        raise CannotCut("a frame of the window isn't one its STREAMINFO allows")
    length = read[2]
    if len(frame) < length + 2:
        raise CannotCut("a frame of the window is shorter than its own header")
    coded = _coded_length(frame[4])
    old_head = frame[:length]
    body = frame[:4] + coded_number(number) + frame[4 + coded:length - 1]
    new_head = body + bytes((_crc8(body),))
    if new_head == old_head:
        return bytes(frame)
    rest = len(frame) - length - 2
    old_crc = int.from_bytes(frame[-2:], "big")
    new_crc = old_crc ^ _crc16_after(_crc16(new_head) ^ _crc16(old_head), rest)
    return new_head + frame[length:-2] + new_crc.to_bytes(2, "big")


@dataclass(frozen=True)
class Window:
    """A stretch of a song as a FLAC file of its own."""

    data: bytes
    #? the song's sample the window's first sample is, how many it holds, and at what rate - so the
    #? page knows exactly where in the song it sits: from first / rate, for samples / rate seconds
    first: int
    samples: int
    rate: int
    #? the song's whole length, in samples (0 when STREAMINFO didn't say)
    song_samples: int


def flac_of_frames(info: StreamInfo, frames: list[tuple[bytes, int]], first: int,
                   song_samples: int = 0) -> Window:
    """
    The frames - (bytes, block size), in order, the first of them starting at the song's sample
    `first` - as a FLAC file of their own: 'fLaC', STREAMINFO alone and rewritten, then the frames
    renumbered from 0 (see the module's docstring).
    """
    if not frames:
        raise CannotCut("no frames to make a window of")
    renumbered, position = [], 0
    for index, (frame, block) in enumerate(frames):
        #? the blocking strategy bit: a variable-block stream numbers its frames by their first sample
        variable = frame[1] & 0x01
        renumbered.append(renumber(frame, info, position if variable else index))
        position += block
    sizes = [len(frame) for frame in renumbered]
    packed = (int.from_bytes(info.raw[10:18], "big") & ~0xFFFFFFFFF) | position
    streaminfo = (info.raw[0:4] + min(sizes).to_bytes(3, "big") + max(sizes).to_bytes(3, "big")
                  + packed.to_bytes(8, "big") + bytes(16))
    data = b"".join([b"fLaC", bytes((0x80, 0, 0, len(streaminfo))), streaminfo, *renumbered])
    return Window(data=data, first=first, samples=position, rate=info.sample_rate, song_samples=song_samples)


# ---------------------------------------------------------------- reading deadwax's own MP4s

Read = Callable[[int, int], bytes]


def _boxes(data: bytes, start: int = 0, end: int | None = None) -> list[tuple[bytes, int, int]]:
    """[(type, body start, box end)] of the boxes between start and end of `data`."""
    end = len(data) if end is None else end
    found, pos = [], start
    while pos + 8 <= end:
        size, kind = struct.unpack(">I4s", data[pos:pos + 8])
        header = 8
        if size == 1:
            if pos + 16 > end:
                raise CannotCut("a box runs past the end")
            size, header = struct.unpack(">Q", data[pos + 8:pos + 16])[0], 16
        if size < header or pos + size > end:
            raise CannotCut("a box runs past the end of the one it is in")
        found.append((kind, pos + header, pos + size))
        pos += size
    if pos != end:
        raise CannotCut("bytes left over after the last box")
    return found


def _inside(data: bytes, *path: bytes) -> bytes:
    """The body of the one box at `path` (moov, trak, ...)."""
    start, end = 0, len(data)
    for kind in path:
        matches = [(s, e) for k, s, e in _boxes(data, start, end) if k == kind]
        if len(matches) != 1:
            raise CannotCut(f"{len(matches)} {kind.decode('latin-1')} boxes where there should be one")
        start, end = matches[0]
    return data[start:end]


def _streaminfo(moov: bytes) -> StreamInfo:
    """STREAMINFO out of the 'dfLa' box in the moov, where both kinds of MP4 carry it alone."""
    at = moov.find(b"dfLa")
    if at < 4 or moov[at + 8:at + 12] != bytes((0x80, 0, 0, 34)):
        raise CannotCut("its moov carries no STREAMINFO")
    try:
        return _parse_streaminfo(moov[at + 12:at + 46])
    except ValueError as e:
        raise CannotCut(f"its STREAMINFO isn't valid ({e})") from e


@dataclass(frozen=True)
class SongIndex:
    """
    Where the audio of a song's MP4 is: each piece that can be read whole - a frame of the plain
    MP4, a fragment (moof and mdat, about a second of frames) of the fragmented one - by its offset
    in the file, its size, the song's sample it starts at and how many samples it holds.
    """

    info: StreamInfo
    fragmented: bool
    offsets: tuple[int, ...]
    sizes: tuple[int, ...]
    firsts: tuple[int, ...]
    samples: tuple[int, ...]

    @property
    def total(self) -> int:
        return self.firsts[-1] + self.samples[-1] if self.firsts else 0


def _head(read: Read, size: int) -> tuple[list[tuple[bytes, int, int]], dict[bytes, bytes]]:
    """The file's top-level boxes up to its audio, and the bodies of moov and sidx, read box by box -
    never the audio itself."""
    pos, tops, bodies = 0, [], {}
    while pos + 8 <= size:
        header = read(pos, 16)
        if len(header) < 8:
            raise CannotCut("the file ends inside a box header")
        length, kind = struct.unpack(">I4s", header[:8])
        skip = 8
        if length == 1:
            if len(header) < 16:
                raise CannotCut("the file ends inside a box header")
            length, skip = struct.unpack(">Q", header[8:16])[0], 16
        if length < skip or pos + length > size:
            raise CannotCut("a box runs past the end of the file")
        tops.append((kind, pos, length))
        if kind in (b"mdat", b"moof"):
            break
        if kind in (b"moov", b"sidx"):
            body = read(pos + skip, length - skip)
            if len(body) != length - skip:
                raise CannotCut("the file ends inside its moov")
            bodies[kind] = body
        pos += length
    return tops, bodies


def _table(body: bytes, entry: str) -> list[tuple[int, ...]]:
    """A full box's table: its entry count, then that many entries of `entry`'s struct format."""
    if len(body) < 8:
        raise CannotCut("a table box is too short")
    count = struct.unpack(">I", body[4:8])[0]
    step = struct.calcsize(">" + entry)
    if len(body) < 8 + count * step:
        raise CannotCut("a table box is shorter than its count says")
    return list(struct.iter_unpack(">" + entry, body[8:8 + count * step]))


def _plain_index(moov: bytes) -> SongIndex:
    """Every frame of a plain MP4, from its sample tables (flac_mp4._moov wrote them)."""
    info = _streaminfo(moov)
    stbl = _inside(moov, b"trak", b"mdia", b"minf", b"stbl")
    kinds = {kind: (start, end) for kind, start, end in _boxes(stbl)}
    if not {b"stts", b"stsc", b"stsz"} <= kinds.keys() or not ({b"stco", b"co64"} & kinds.keys()):
        raise CannotCut("its sample tables aren't all there")
    body = lambda kind: stbl[kinds[kind][0]:kinds[kind][1]]  # noqa: E731
    durations = [delta for count, delta in _table(body(b"stts"), "II") for _ in range(count)]
    stsz = body(b"stsz")
    if len(stsz) < 12:
        raise CannotCut("its size table is too short")
    fixed, count = struct.unpack(">II", stsz[4:12])
    if fixed:
        sizes = [fixed] * count
    else:
        if len(stsz) < 12 + 4 * count:
            raise CannotCut("its size table is shorter than its count says")
        sizes = list(struct.unpack(f">{count}I", stsz[12:12 + 4 * count]))
    chunks = [row[0] for row in (_table(body(b"stco"), "I") if b"stco" in kinds else _table(body(b"co64"), "Q"))]
    rows = _table(body(b"stsc"), "III")
    if len(durations) != len(sizes) or not rows or not chunks:
        raise CannotCut("its sample tables don't agree with each other")
    offsets, sample = [], 0
    for at, (first_chunk, per_chunk, _) in enumerate(rows):
        last_chunk = rows[at + 1][0] - 1 if at + 1 < len(rows) else len(chunks)
        for chunk in range(first_chunk, last_chunk + 1):
            if chunk < 1 or chunk > len(chunks):
                raise CannotCut("its chunk table doesn't agree with its chunks")
            offset = chunks[chunk - 1]
            for _ in range(per_chunk):
                if sample >= len(sizes):
                    raise CannotCut("its chunks hold more frames than its size table")
                offsets.append(offset)
                offset += sizes[sample]
                sample += 1
    if sample != len(sizes):
        raise CannotCut("its chunks hold fewer frames than its size table")
    firsts, running = [], 0
    for duration in durations:
        firsts.append(running)
        running += duration
    return SongIndex(info=info, fragmented=False, offsets=tuple(offsets), sizes=tuple(sizes),
                     firsts=tuple(firsts), samples=tuple(durations))


def _fragmented_index(moov: bytes, sidx: bytes, sidx_end: int) -> SongIndex:
    """Every fragment of a fragmented MP4, from its index (flac_mp4.fmp4_layout wrote it)."""
    info = _streaminfo(moov)
    if len(sidx) < 24 or sidx[0] != 0:
        raise CannotCut("its fragment index isn't the kind deadwax writes")
    _, timescale, earliest, first_offset, _, count = struct.unpack(">IIIIHH", sidx[4:24])
    if timescale != info.sample_rate or len(sidx) < 24 + 12 * count:
        raise CannotCut("its fragment index doesn't agree with its STREAMINFO")
    offsets, sizes, firsts, samples = [], [], [], []
    offset, sample = sidx_end + first_offset, earliest
    for at in range(count):
        size, duration, _ = struct.unpack(">III", sidx[24 + 12 * at:36 + 12 * at])
        size &= 0x7FFFFFFF
        offsets.append(offset)
        sizes.append(size)
        firsts.append(sample)
        samples.append(duration)
        offset += size
        sample += duration
    return SongIndex(info=info, fragmented=True, offsets=tuple(offsets), sizes=tuple(sizes),
                     firsts=tuple(firsts), samples=tuple(samples))


def song_index(read: Read, size: int) -> SongIndex:
    """Where the audio of one of deadwax's MP4s of a song is - a plain one or a fragmented one."""
    tops, bodies = _head(read, size)
    kinds = [kind for kind, _, _ in tops]
    if kinds[:3] == [b"ftyp", b"moov", b"mdat"] and b"moov" in bodies:
        index = _plain_index(bodies[b"moov"])
    elif kinds[:4] == [b"ftyp", b"moov", b"sidx", b"moof"] and b"sidx" in bodies:
        _, sidx_at, sidx_length = tops[2]
        index = _fragmented_index(bodies[b"moov"], bodies[b"sidx"], sidx_at + sidx_length)
    else:
        raise CannotCut("it isn't an MP4 laid out as deadwax lays them out")
    if not index.offsets or index.offsets[-1] + index.sizes[-1] > size:
        raise CannotCut("its tables point past the end of the file")
    return index


def _fragment_frames(fragment: bytes, info: StreamInfo) -> list[tuple[bytes, int]]:
    """A fragment's frames, (bytes, block size), from its own table (flac_mp4._fragment wrote it)."""
    tops = _boxes(fragment)
    if [kind for kind, _, _ in tops] != [b"moof", b"mdat"]:
        raise CannotCut("a fragment isn't a moof and an mdat")
    traf = _inside(fragment[tops[0][1]:tops[0][2]], b"traf")
    parts = {kind: traf[start:end] for kind, start, end in _boxes(traf)}
    tfhd, trun = parts.get(b"tfhd"), parts.get(b"trun")
    if tfhd is None or trun is None or len(tfhd) < 20 or len(trun) < 12:
        raise CannotCut("a fragment's table isn't all there")
    default_duration = struct.unpack(">I", tfhd[8:12])[0]
    flags = int.from_bytes(trun[1:4], "big")
    count, data_offset = struct.unpack(">Ii", trun[4:12])
    durations_given = bool(flags & 0x000100)
    if not flags & 0x000200:
        raise CannotCut("a fragment's table gives no sizes")
    step = 8 if durations_given else 4
    if len(trun) < 12 + step * count:
        raise CannotCut("a fragment's table is shorter than its count says")
    frames, pos = [], data_offset
    for at in range(count):
        row = trun[12 + step * at:12 + step * (at + 1)]
        duration, size = struct.unpack(">II", row) if durations_given else (default_duration, struct.unpack(">I", row)[0])
        if pos + size > len(fragment):
            raise CannotCut("a fragment's frames run past its end")
        frames.append((fragment[pos:pos + size], duration))
        pos += size
    if pos != tops[1][2]:
        raise CannotCut("a fragment's frames don't fill its mdat")
    return frames


def cut_window(read: Read, size: int, at: float, seconds: float, max_bytes: int) -> Window:
    """
    The stretch of the song from `at` seconds for `seconds` - as frames, or for a fragmented MP4 as
    whole fragments, so it starts at or a little before `at` and runs to or a little past its end -
    as a FLAC file of its own (flac_of_frames). Never more than `max_bytes` of audio, bar the one
    piece `at` falls in, which is always there: a hi-res song's window is shorter than asked, which
    the page reads off the answer. PastTheEnd for an
    `at` at or after the end of the song; CannotCut for a file not laid out as deadwax lays them out.
    """
    index = song_index(read, size)
    rate = index.info.sample_rate
    start = max(0, int(at * rate))
    if start >= index.total:
        raise PastTheEnd(f"the song is {index.total / rate:.3f} s long")
    end = start + max(1, int(seconds * rate))
    lo = max(0, bisect_right(index.firsts, start) - 1)
    hi, held = lo, 0
    while hi < len(index.firsts) and index.firsts[hi] < end and (hi == lo or held + index.sizes[hi] <= max_bytes):
        held += index.sizes[hi]
        hi += 1
    if index.fragmented:
        frames = []
        for piece in range(lo, hi):
            fragment = read(index.offsets[piece], index.sizes[piece])
            if len(fragment) != index.sizes[piece]:
                raise CannotCut("the file ends inside a fragment")
            got = _fragment_frames(fragment, index.info)
            if sum(block for _, block in got) != index.samples[piece]:
                raise CannotCut("a fragment's frames don't hold what its index says")
            frames += got
    else:
        first, last = index.offsets[lo], index.offsets[hi - 1] + index.sizes[hi - 1]
        audio = read(first, last - first)
        if len(audio) != last - first:
            raise CannotCut("the file ends inside its audio")
        frames = []
        for piece in range(lo, hi):
            begin = index.offsets[piece] - first
            frames.append((audio[begin:begin + index.sizes[piece]], index.samples[piece]))
    total = index.info.total_samples or index.total
    return flac_of_frames(index.info, frames, index.firsts[lo], song_samples=total)
