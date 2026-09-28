"""
A FLAC file repackaged as an MP4 holding the very same FLAC frames - for Safari's seek bar.

Why: Safari plays <audio> through AVFoundation, and AVFoundation does not land a seek in a FLAC
file where it was asked to. Measured on a Mac (see "Seeking (1.1.0-player.2)" in CLAUDE.md) it
landed 2-8 s off in a song-like file and up to 50 s off in a stress file, seek table or not, while
reporting the time asked for; James saw 3 s and 8 s on his iPhone. The SAME frames in an MP4
landed exactly, because an MP4 carries a table of every frame's size and duration, and a player
seeks by arithmetic on that table instead of by guessing a byte offset from the bit rate.

So this rewraps a FLAC stream, following xiph's "Encapsulation of FLAC in ISO Base Media File
Format" (doc/isoflac.txt in the flac repository): one MP4 sample per FLAC frame, the frames'
bytes untouched, STREAMINFO carried in a 'dfLa' box inside an 'fLaC' sample entry. Nothing is
decoded or encoded - it is lossless by construction and costs one pass of `bytes.find` over the
file. No ffmpeg: the image is python-slim and stays that way.

The risky part is finding where each frame ends, since FLAC has no index of its frames: a frame
ends where the next one's sync code begins, and the same two bytes can turn up inside audio
data. `_split_frames` says how that is made safe. When anything about the stream is not as it
should be, this raises rather than guesses (`CannotRepackage`, a ValueError), and the caller
serves the FLAC as it is - which plays, just seeks badly in Safari. A wrong MP4 would be worse
than none.

Pure: bytes in, bytes out, no I/O.
"""

import struct
from dataclasses import dataclass


class CannotRepackage(ValueError):
    """This file can't become an MP4 here - serve the original instead."""


class NotFlac(CannotRepackage):
    """The input isn't a FLAC stream at all."""


class Unsupported(CannotRepackage):
    """A FLAC stream, but not one this can repackage with certainty."""


#? A bound on the memory: the input and the output are both held whole. Ten minutes of CD audio
#? is ~60 MB and an hour of 24/192 two or three GB; past 1 GiB the caller keeps the FLAC.
MAX_INPUT_BYTES = 1 << 30

#? Sync codes that turn out not to start a frame are about one per 90 KB of real FLAC (measured on
#? CD and 24/96 files). A file with far more - by accident or by design - would have every one
#? checked, so past one per 256 bytes (and a floor for small files) it is refused instead.
FALSE_SYNC_BUDGET = (4096, 256)

#? How much audio goes in one MP4 chunk (a run of samples stored back to back, found through one
#? entry of the chunk offset table). A player finds a sample by taking its chunk's offset and
#? adding the sizes of the samples before it in that chunk. One chunk for the whole file would
#? leave that sum running over the whole file; one chunk per frame would make the offset table as
#? large as the size table for nothing, the frames being contiguous anyway. About a second keeps
#? both small - a 5-minute song has ~300 offsets - and is not what makes a seek land: AVFoundation
#? landed exactly in ffmpeg's MP4 of the same file too, whose chunks ran to a minute.
CHUNK_SECONDS = 1

_ID3 = b"ID3"
_MARKER = b"fLaC"
_STREAMINFO = 0
_STREAMINFO_LENGTH = 34

#? frame header code -> value (RFC 9639, section 9.1). Codes not listed are reserved (block size
#? 0, sample size 3) or mean "read it from the end of the header" (block size 6/7, rate 12-14).
_BLOCK_SIZES = {1: 192, 2: 576, 3: 1152, 4: 2304, 5: 4608, 8: 256, 9: 512, 10: 1024, 11: 2048,
                12: 4096, 13: 8192, 14: 16384, 15: 32768}
_RATES = {1: 88200, 2: 176400, 3: 192000, 4: 8000, 5: 16000, 6: 22050, 7: 24000, 8: 32000,
          9: 44100, 10: 48000, 11: 96000}
_SAMPLE_SIZES = {1: 8, 2: 12, 4: 16, 5: 20, 6: 24, 7: 32}


def _crc_table(poly: int, width: int) -> tuple[int, ...]:
    top, mask = 1 << (width - 1), (1 << width) - 1
    table = []
    for byte in range(256):
        crc = byte << (width - 8)
        for _ in range(8):
            crc = ((crc << 1) ^ poly) if crc & top else (crc << 1)
        table.append(crc & mask)
    return tuple(table)


#? FLAC's two checksums: CRC-8 (x^8 + x^2 + x + 1) over each frame header, CRC-16 (x^16 + x^15 +
#? x^2 + 1) over each whole frame. Both start at zero with nothing reflected, so a frame including
#? its own CRC-16 sums to zero - which is how a frame's END is checked below.
_CRC8 = _crc_table(0x07, 8)
_CRC16 = _crc_table(0x8005, 16)


def _crc8(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc = _CRC8[crc ^ byte]
    return crc


def _crc16(data: bytes) -> int:
    crc = 0
    for byte in data:
        crc = ((crc << 8) & 0xFFFF) ^ _CRC16[(crc >> 8) ^ byte]
    return crc


@dataclass(frozen=True)
class StreamInfo:
    """FLAC's STREAMINFO block: what every frame has to agree with."""

    raw: bytes                  # the block's 34 bytes, carried into 'dfLa' as they are
    min_block: int
    max_block: int
    sample_rate: int
    channels: int
    bits_per_sample: int
    total_samples: int          # 0 when the encoder didn't know


@dataclass(frozen=True)
class FlacFrames:
    """Where the audio frames of a FLAC file are, and how many samples each holds."""

    info: StreamInfo
    starts: tuple[int, ...]     # offset of each frame in the file
    end: int                    # where the last frame ends (a trailing tag isn't audio)
    block_sizes: tuple[int, ...]

    def sizes(self) -> list[int]:
        bounds = self.starts[1:] + (self.end,)
        return [b - a for a, b in zip(self.starts, bounds)]


def _skip_id3v2(data: bytes) -> int:
    """Where the FLAC stream starts: after any ID3v2 tags put in front of it."""
    pos = 0
    #? more than one tag in a row is legal, if rare; a handful is plenty
    for _ in range(8):
        if not data.startswith(_ID3, pos):
            break
        header = data[pos:pos + 10]
        if len(header) < 10 or any(b & 0x80 for b in header[6:10]):
            raise NotFlac("an ID3v2 tag in front that isn't a valid one")
        size = (header[6] << 21) | (header[7] << 14) | (header[8] << 7) | header[9]
        footer = 10 if header[5] & 0x10 else 0
        pos += 10 + size + footer
    return pos


def _read_metadata(data: bytes, pos: int) -> tuple[StreamInfo, int]:
    """STREAMINFO, and where the first audio frame should begin."""
    if not data.startswith(_MARKER, pos):
        raise NotFlac("no 'fLaC' marker at the start of the file")
    pos += 4
    info = None
    while True:
        if pos + 4 > len(data):
            raise Unsupported("the metadata runs past the end of the file")
        head = data[pos]
        kind, last = head & 0x7F, head & 0x80
        length = int.from_bytes(data[pos + 1:pos + 4], "big")
        body = data[pos + 4:pos + 4 + length]
        if len(body) < length:
            raise Unsupported("the metadata runs past the end of the file")
        if info is None:
            if kind != _STREAMINFO or length != _STREAMINFO_LENGTH:
                raise Unsupported("the first metadata block isn't STREAMINFO")
            info = _parse_streaminfo(body)
        elif kind == 127:
            raise Unsupported("a metadata block of the invalid type 127")
        pos += 4 + length
        if last:
            return info, pos


def _parse_streaminfo(raw: bytes) -> StreamInfo:
    min_block, max_block = struct.unpack(">HH", raw[0:4])
    packed = int.from_bytes(raw[10:18], "big")
    info = StreamInfo(
        raw=bytes(raw),
        min_block=min_block,
        max_block=max_block,
        sample_rate=packed >> 44,
        channels=((packed >> 41) & 0x7) + 1,
        bits_per_sample=((packed >> 36) & 0x1F) + 1,
        total_samples=packed & 0xFFFFFFFFF,
    )
    if info.sample_rate == 0:
        raise Unsupported("STREAMINFO gives no sample rate")
    if info.max_block < 16 or info.min_block > info.max_block:
        raise Unsupported(f"STREAMINFO's block sizes ({min_block}-{max_block}) aren't valid")
    if info.bits_per_sample < 4:
        raise Unsupported(f"{info.bits_per_sample}-bit samples aren't valid FLAC")
    return info


def _coded_number(n: int) -> bytes:
    """A frame or sample number as a frame header codes it (UTF-8's scheme, stretched to 36 bits).

    Only the shortest coding is ever written by an encoder, and comparing against it is both the
    fastest check and the strictest: an over-long coding that happened to carry the right value
    is not accepted.
    """
    if n < 0x80:
        return bytes((n,))
    for extra, limit in ((1, 1 << 11), (2, 1 << 16), (3, 1 << 21), (4, 1 << 26), (5, 1 << 31), (6, 1 << 36)):
        if n < limit:
            lead = (0xFF << (7 - extra)) & 0xFF
            tail = [0x80 | ((n >> (6 * i)) & 0x3F) for i in range(extra - 1, -1, -1)]
            return bytes([lead | (n >> (6 * extra))] + tail)
    raise Unsupported("a sample number past 36 bits")


def _frame_header(data: bytes, pos: int, info: StreamInfo, numbers: tuple[bytes, ...]):
    """(which of `numbers` it carries, its block size, its length) for a frame header at `pos`.

    None unless EVERYTHING about it is right: every fixed field agrees with STREAMINFO, the
    reserved bits are clear, the frame (or sample) number is exactly one of those given, coded
    the shortest way, and the header's own CRC-8 checks out. The caller has already matched the
    sync code and blocking-strategy bit.
    """
    end = len(data)
    if pos + 6 > end:
        return None
    b2, b3 = data[pos + 2], data[pos + 3]
    block_code, rate_code = b2 >> 4, b2 & 0x0F
    channel_code, size_code = b3 >> 4, (b3 >> 1) & 0x07
    if b3 & 0x01 or block_code == 0 or rate_code == 0x0F:
        return None
    channels = channel_code + 1 if channel_code < 8 else 2 if channel_code <= 10 else 0
    if channels != info.channels:
        return None
    if size_code and _SAMPLE_SIZES.get(size_code) != info.bits_per_sample:
        return None
    if 0 < rate_code < 12 and _RATES[rate_code] != info.sample_rate:
        return None
    p = pos + 4
    for which, coded in enumerate(numbers):
        if data.startswith(coded, p):
            p += len(coded)
            break
    else:
        return None
    if block_code == 6:
        if p + 1 > end:
            return None
        block_size = data[p] + 1
        p += 1
    elif block_code == 7:
        if p + 2 > end:
            return None
        block_size = ((data[p] << 8) | data[p + 1]) + 1
        p += 2
    else:
        block_size = _BLOCK_SIZES[block_code]
    if block_size > info.max_block:
        return None
    if rate_code >= 12:
        if rate_code == 12:
            if p + 1 > end:
                return None
            rate = data[p] * 1000
            p += 1
        else:
            if p + 2 > end:
                return None
            rate = (data[p] << 8) | data[p + 1]
            rate *= 10 if rate_code == 14 else 1
            p += 2
        if rate != info.sample_rate:
            return None
    if p >= end or _crc8(data[pos:p]) != data[p]:
        return None
    return which, block_size, p + 1 - pos


def _audio_ends(data: bytes, start: int) -> list[int]:
    """Where the last frame could end: the end of the file, or before a tag appended to it.

    ID3v1 (and its "TAG+" extension) and APEv2 are the tags that turn up at the end of FLAC
    files. Each is only a candidate - the last frame's CRC-16 decides - so a frame whose last
    bytes happen to spell "TAG" is not cut short by it.
    """
    ends = [len(data)]
    end = len(data)
    if end - 128 > start and data[end - 128:end - 125] == b"TAG":
        end -= 128
        if end - 227 > start and data[end - 227:end - 223] == b"TAG+":
            end -= 227
        ends.append(end)
    if end - 32 > start and data[end - 32:end - 24] == b"APETAGEX":
        size, flags = struct.unpack("<I4xI", data[end - 20:end - 8])
        ape = size + (32 if flags & 0x80000000 else 0)
        if end - ape > start:
            ends.append(end - ape)
    return ends


def _split_frames(data: bytes, first: int, info: StreamInfo) -> FlacFrames:
    """Every audio frame from `first` on, found without a single false split.

    A frame begins with a sync code (0xFFF8, or 0xFFF9 in a variable-block-size stream), and the
    same two bytes turn up inside compressed audio every few tens of kilobytes. So a candidate is
    taken as the next frame only if its header is right in every particular (`_frame_header`):
    fields that agree with STREAMINFO, a valid CRC-8, and exactly the NEXT frame number (or, in a
    variable-block-size stream, the next sample number). A stretch of audio data passes all of
    that by chance about once in 2^40 bytes at worst, and once in 2^48 once frame numbers take
    two bytes to write (past frame 127, a few seconds in).

    That is not left to chance either. Were a false header ever taken as frame k, the real frame
    k's header would still come after it, before frame k+1's - and it would carry a number already
    used. So a header carrying the number just used is watched for, and when one appears the
    frame's own CRC-16 settles which of the two is real: the frame before them has to checksum
    to zero from its start to the real one. Neither doing so means the stream isn't what it
    claims, and it is refused. (Checksumming every frame would be certain without any of this,
    but it is a byte-at-a-time loop in Python - seconds for an album track - where this is
    milliseconds.)

    The LAST frame is always checksummed, since nothing after it says where it ends: that is how
    a tag appended to the file is left out, and how a file cut short is refused.
    """
    if data[first:first + 1] != b"\xff" or data[first + 1:first + 2] not in (b"\xf8", b"\xf9"):
        raise Unsupported("no audio frame where the metadata ends")
    sync = data[first:first + 2]
    fixed = sync == b"\xff\xf8"
    got = _frame_header(data, first, info, (_coded_number(0),))
    if got is None:
        raise Unsupported("the first audio frame's header isn't valid")
    _, block_size, header_length = got
    starts, blocks, numbers = [first], [block_size], [0]
    search = first + header_length
    budget = FALSE_SYNC_BUDGET[0] + len(data) // FALSE_SYNC_BUDGET[1]
    while True:
        #? the number the frame just found carried, and the one the next frame must carry
        last = numbers[-1]
        wanted = last + 1 if fixed else last + blocks[-1]
        coded = (_coded_number(wanted), _coded_number(last))
        while True:
            at = data.find(sync, search)
            if at < 0:
                break
            got = _frame_header(data, at, info, coded)
            if got is not None:
                break
            search = at + 1
            budget -= 1
            if budget < 0:
                raise Unsupported("far too many sync codes that start no frame")
        if at < 0:
            break
        which, block_size, header_length = got
        if which == 0:
            starts.append(at)
            blocks.append(block_size)
            numbers.append(wanted)
            search = at + header_length
            continue
        #? a second header carrying the number already given to the frame at starts[-1]
        if len(starts) == 1:
            #? the first frame is where the metadata ends, so this one is inside its audio
            search = at + 1
            continue
        before = starts[-2]
        if _crc16(data[before:starts[-1]]) == 0:
            search = at + 1
        elif _crc16(data[before:at]) == 0:
            starts[-1], blocks[-1] = at, block_size
            search = at + header_length
        else:
            raise Unsupported(f"two frames claim to be number {last}, and neither checks out")
    ends = [end for end in _audio_ends(data, starts[-1]) if _crc16(data[starts[-1]:end]) == 0]
    if not ends and len(starts) > 1:
        #? the last header found may have been audio data in the real last frame, numbered as
        #? if a frame followed it: then the frame before it checks out to the end of the file
        ends = [end for end in _audio_ends(data, starts[-2]) if _crc16(data[starts[-2]:end]) == 0]
        if ends:
            del starts[-1], blocks[-1], numbers[-1]
    if not ends:
        raise Unsupported("the last frame's checksum is wrong - the file may be cut short")
    end = ends[0]
    total = sum(blocks)
    if info.total_samples and total != info.total_samples:
        raise Unsupported(f"the frames hold {total} samples where STREAMINFO says {info.total_samples}")
    if fixed and any(size != blocks[0] for size in blocks[:-1]):
        raise Unsupported("a fixed-block-size stream whose frames change size")
    return FlacFrames(info=info, starts=tuple(starts), end=end, block_sizes=tuple(blocks))


def find_frames(data: bytes) -> FlacFrames:
    """The audio frames of a FLAC file, or NotFlac / Unsupported."""
    if len(data) > MAX_INPUT_BYTES:
        raise Unsupported(f"larger than {MAX_INPUT_BYTES >> 20} MiB")
    info, first = _read_metadata(data, _skip_id3v2(data))
    if first >= len(data):
        raise Unsupported("no audio frames")
    return _split_frames(data, first, info)


# --- the MP4 --------------------------------------------------------------------------------

def _box(kind: bytes, *parts: bytes) -> bytes:
    body = b"".join(parts)
    return struct.pack(">I4s", 8 + len(body), kind) + body


def _full_box(kind: bytes, version: int, flags: int, *parts: bytes) -> bytes:
    return _box(kind, struct.pack(">I", (version << 24) | flags), *parts)


#? the identity matrix, in the 16.16 / 2.30 fixed point mvhd and tkhd use
_MATRIX = struct.pack(">9I", 0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000)
_LANGUAGE_UND = ((ord("u") - 0x60) << 10) | ((ord("n") - 0x60) << 5) | (ord("d") - 0x60)


def _entry_rate(rate: int) -> int:
    """The sample entry's 16.16 sample rate, as isoflac.txt says it must be written.

    Rates up to 65535 Hz go in as they are. Above that the field can't hold them, and the spec
    asks for "the greatest expressible regular division of that rate" - 48000.0 for 96 and 192
    kHz - or 65535.0 where there is none. The real rate is always STREAMINFO's, in 'dfLa', and
    the media timescale; a reader is told to take it from there.
    """
    value = rate
    while value > 0xFFFF and value % 2 == 0:
        value //= 2
    return (value if value <= 0xFFFF else 0xFFFF) << 16


def _chunks(frames: FlacFrames) -> list[int]:
    """How many frames go in each chunk: whole frames, about CHUNK_SECONDS of audio a chunk."""
    per_chunk, counts, held, samples = frames.info.sample_rate * CHUNK_SECONDS, [], 0, 0
    for block in frames.block_sizes:
        held += 1
        samples += block
        if samples >= per_chunk:
            counts.append(held)
            held = samples = 0
    if held:
        counts.append(held)
    return counts


def _runs(values) -> list[list[int]]:
    """[value, how many in a row] for each run of equal values."""
    runs: list[list[int]] = []
    for value in values:
        if runs and runs[-1][0] == value:
            runs[-1][1] += 1
        else:
            runs.append([value, 1])
    return runs


def _moov(frames: FlacFrames, audio_at: int) -> bytes:
    """The movie box, for frames whose first byte will sit at `audio_at` in the output."""
    info = frames.info
    duration = sum(frames.block_sizes)
    #? version 1 only when a 32-bit duration can't hold it - many hours at a high rate
    long = duration > 0xFFFFFFFF
    version = 1 if long else 0
    times = struct.pack(">QQ", 0, 0) if long else struct.pack(">II", 0, 0)
    length = struct.pack(">Q" if long else ">I", duration)

    #? the movie's timescale is the sample rate too, so its duration is as exact as the media's
    mvhd = _full_box(b"mvhd", version, 0, times, struct.pack(">I", info.sample_rate), length,
                     struct.pack(">IH10x", 0x10000, 0x0100), _MATRIX, bytes(24),
                     struct.pack(">I", 2))
    #? flags 7: enabled, in the movie, in its preview - as isoflac.txt's example has it
    tkhd = _full_box(b"tkhd", version, 7, times, struct.pack(">II", 1, 0), length,
                     struct.pack(">8xHHH2x", 0, 0, 0x0100), _MATRIX, struct.pack(">II", 0, 0))
    mdhd = _full_box(b"mdhd", version, 0, times, struct.pack(">I", info.sample_rate), length,
                     struct.pack(">HH", _LANGUAGE_UND, 0))
    hdlr = _full_box(b"hdlr", 0, 0, struct.pack(">I4s12x", 0, b"soun"), b"SoundHandler\x00")

    dfla = _full_box(b"dfLa", 0, 0, bytes((0x80 | _STREAMINFO,)),
                     len(info.raw).to_bytes(3, "big"), info.raw)
    entry = _box(b"fLaC", bytes(6), struct.pack(">H8xHHHHI", 1, info.channels,
                                                 info.bits_per_sample, 0, 0,
                                                 _entry_rate(info.sample_rate)), dfla)
    stsd = _full_box(b"stsd", 0, 0, struct.pack(">I", 1), entry)

    durations = _runs(frames.block_sizes)
    stts = _full_box(b"stts", 0, 0, struct.pack(">I", len(durations)),
                     b"".join(struct.pack(">II", count, delta) for delta, count in durations))

    counts = _chunks(frames)
    stsc_rows, chunk = [], 1
    for per, run in _runs(counts):
        stsc_rows.append(struct.pack(">III", chunk, per, 1))
        chunk += run
    stsc = _full_box(b"stsc", 0, 0, struct.pack(">I", len(stsc_rows)), *stsc_rows)

    sizes = frames.sizes()
    stsz = _full_box(b"stsz", 0, 0, struct.pack(">II", 0, len(sizes)),
                     struct.pack(f">{len(sizes)}I", *sizes))

    offsets, index, first = [], 0, frames.starts[0]
    for count in counts:
        offsets.append(audio_at + frames.starts[index] - first)
        index += count
    if offsets[-1] > 0xFFFFFFFF:
        stco = _full_box(b"co64", 0, 0, struct.pack(f">I{len(offsets)}Q", len(offsets), *offsets))
    else:
        stco = _full_box(b"stco", 0, 0, struct.pack(f">I{len(offsets)}I", len(offsets), *offsets))

    #? no stss: every FLAC frame is a sync sample, which is what its absence says (isoflac.txt
    #? 3.3.6.1 forbids one); and no edit list, so the track plays from its first sample
    stbl = _box(b"stbl", stsd, stts, stsc, stsz, stco)
    dinf = _box(b"dinf", _full_box(b"dref", 0, 0, struct.pack(">I", 1), _full_box(b"url ", 0, 1)))
    minf = _box(b"minf", _full_box(b"smhd", 0, 0, bytes(4)), dinf, stbl)
    trak = _box(b"trak", tkhd, _box(b"mdia", mdhd, hdlr, minf))
    return _box(b"moov", mvhd, trak)


#? 'isom' is the brand isoflac.txt requires; the rest is what ffmpeg writes for the same stream,
#? which is the file AVFoundation was first measured seeking exactly in
_FTYP = _box(b"ftyp", b"isom", struct.pack(">I", 0x200), b"isom", b"iso2", b"mp41")


def mp4_layout(data: bytes) -> tuple[bytes, int, int]:
    """The MP4 for the FLAC file `data`, as everything that goes before the audio and where in
    `data` the audio is: the MP4 is `head + data[start:end]`.

    ftyp, then moov, then mdat: the tables come BEFORE the audio, so a player that fetches by
    range can seek without first reading to the end of the file. The audio is the FLAC's own
    frames, untouched, so a caller writing the MP4 out can write the head and then that slice of
    the file it already holds, rather than build a second copy of it (routes/navidrome.py's cache
    does). Raises NotFlac or Unsupported (both CannotRepackage, a ValueError) for anything it
    can't repackage with certainty.
    """
    frames = find_frames(data)
    start, end = frames.starts[0], frames.end
    length = end - start
    #? a 64-bit size only when a 32-bit one can't hold it; never under MAX_INPUT_BYTES
    mdat_header = (struct.pack(">I4s", 8 + length, b"mdat") if 8 + length <= 0xFFFFFFFF
                   else struct.pack(">I4sQ", 1, b"mdat", 16 + length))
    #? the offsets in moov depend on moov's own length, which doesn't depend on them - except
    #? that offsets past 4 GiB take a longer table, so the length is built again until it holds
    head = len(_FTYP) + len(mdat_header)
    size = len(_moov(frames, head))
    moov = _moov(frames, head + size)
    while len(moov) != size:
        size = len(moov)
        moov = _moov(frames, head + size)
    return b"".join((_FTYP, moov, mdat_header)), start, end


def flac_to_mp4(data: bytes) -> bytes:
    """The FLAC file `data` as an MP4 holding the same frames, byte for byte - see mp4_layout().

    Raises NotFlac or Unsupported (both CannotRepackage, a ValueError) for anything it can't
    repackage with certainty.
    """
    if not isinstance(data, bytes):
        data = bytes(data)
    head, start, end = mp4_layout(data)
    return b"".join((head, memoryview(data)[start:end]))
