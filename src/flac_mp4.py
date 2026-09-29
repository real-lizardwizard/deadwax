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
from bisect import bisect_left
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
#? checked, so past one per 256 bytes (and a floor for small files) it is refused instead. A
#? header carrying a number already used counts as one: one of the two starts no frame.
FALSE_SYNC_BUDGET = (4096, 256)

#? A bound on the checksumming, the one part of this done a byte at a time in Python (~15 MB/s).
#? A sum runs no further than a frame can reach (`_reach`) - bar the check of a header repeating
#? the number just used, which spans two frames in a file as it should be - and each stretch is
#? summed once and remembered, so a real file sums its last frame and any tag after it within
#? reach - kilobytes; 2 MB for the largest frame FLAC can hold - and a frame or two more in the
#? rare file with a false header. A file built to be checksummed over and over is refused past
#? this instead of holding a worker thread: about a quarter of a second here, whatever its size.
CHECKSUM_BUDGET = 4 << 20

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


def _crc16(data: bytes, crc: int = 0) -> int:
    """The CRC-16 of `data`, or carried on over it from `crc`, the sum of whatever came before."""
    for byte in data:
        crc = ((crc << 8) & 0xFFFF) ^ _CRC16[(crc >> 8) ^ byte]
    return crc


class _Checksums:
    """The CRC-16s one split asks for, each stretch of the file summed once, within CHECKSUM_BUDGET.

    `upto(origin, end)` is the CRC-16 of data[origin:end]. The questions asked of one origin come
    in order along the file - where its frame was taken to end, then up to each copy of a header
    - so the sum is carried on from where the last answer stopped rather than begun again, and
    every answer is kept, so asking twice costs nothing. A later origin where the sum so far is
    zero - the start of a frame that checked out - carries on too, since a sum that has come back
    to zero goes on exactly as one begun there. Any other origin starts afresh.
    """

    def __init__(self, data: bytes):
        self.data = data
        self.left = CHECKSUM_BUDGET
        self.origin = -1
        self.answers: dict[int, int] = {}
        self.at = self.crc = 0

    def _sum(self, start: int, end: int, crc: int) -> int:
        self.left -= end - start
        if self.left < 0:
            raise Unsupported("far too much checksumming")
        return _crc16(self.data[start:end], crc)

    def upto(self, origin: int, end: int) -> int:
        if origin != self.origin and not (self.origin < origin and self.answers.get(origin) == 0):
            self.origin, self.answers, self.at, self.crc = origin, {origin: 0}, origin, 0
        if end not in self.answers:
            if end < self.at:
                #? not asked in order: begin again rather than answer wrongly
                self.at, self.crc = origin, 0
            self.crc = self._sum(self.at, end, self.crc)
            self.at = end
            self.answers[end] = self.crc
        return self.answers[end]

    def zeros(self, start: int, marks: list[int]) -> set[int]:
        """Which of `marks` (places after `start`, in order) data[start:mark] checksums to zero at,
        in one pass."""
        found, at, crc = set(), start, 0
        for mark in marks:
            crc = self._sum(at, mark, crc)
            at = mark
            if not crc:
                found.add(mark)
        return found


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
    max_framesize: int = 0      # the largest frame's size in bytes; 0 when the encoder didn't know


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
        max_framesize=int.from_bytes(raw[7:10], "big"),
    )
    if info.sample_rate == 0:
        raise Unsupported("STREAMINFO gives no sample rate")
    if info.max_block < 16 or info.min_block > info.max_block:
        raise Unsupported(f"STREAMINFO's block sizes ({min_block}-{max_block}) aren't valid")
    if info.bits_per_sample < 4:
        raise Unsupported(f"{info.bits_per_sample}-bit samples aren't valid FLAC")
    return info


def _reach(info: StreamInfo) -> int:
    """The most bytes one frame of this stream can take up.

    STREAMINFO's largest frame, when the encoder wrote one: libFLAC and ffmpeg write the true
    figure (ffmpeg an upper bound when it can't go back for it, libFLAC 0), and none of the 217
    real files this was checked against has a frame past it. Otherwise, a frame of the largest
    block with every sample stored as it is - a stereo side channel's extra bit included - which
    no encoder goes past, since storing the samples verbatim is always one of the ways it can
    write a frame (ffmpeg's ff_flac_get_max_frame_size is the same sum).
    """
    if info.max_framesize:
        return info.max_framesize
    bits = info.max_block * info.channels * info.bits_per_sample
    if info.channels == 2:
        bits += info.max_block
    #? a header of 16 bytes at most, a subframe header per channel with room for its count of
    #? wasted bits, the samples, and the CRC-16
    return 16 + info.channels * ((info.bits_per_sample + 14) // 8) + (bits + 7) // 8 + 2


#? a coded number's first byte -> how many bytes follow it (UTF-8's scheme, stretched to 36 bits:
#? 110xxxxx one, 1110xxxx two ... 11111110 six); 0 for a byte that can't begin one (10xxxxxx,
#? 0xFF) - the one-byte numbers, below 0x80, are read before this is looked at
_NUMBER_TAILS = tuple(8 - (lead ^ 0xFF).bit_length() - 1 if 0xC0 <= lead < 0xFF else 0 for lead in range(256))
#? the least number each length may carry: anything less has a shorter coding, and only the
#? shortest is ever written by an encoder
_SHORTEST = (0, 1 << 7, 1 << 11, 1 << 16, 1 << 21, 1 << 26, 1 << 31)


def _frame_header(data: bytes, pos: int, info: StreamInfo):
    """(the frame or sample number it carries, its block size, its length) for a frame header at
    `pos`.

    None unless EVERYTHING about it is right: every fixed field agrees with STREAMINFO, the
    reserved bits are clear, the number is coded the shortest way, and the header's own CRC-8
    checks out. Which number it ought to carry is the caller's to judge. The caller has already
    matched the sync code and blocking-strategy bit.
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
    lead = data[p]
    if lead < 0x80:
        number = lead
        p += 1
    else:
        tail = _NUMBER_TAILS[lead]
        if not tail or p + tail >= end:
            return None
        number = lead & (0x3F >> tail)
        for byte in data[p + 1:p + 1 + tail]:
            if byte & 0xC0 != 0x80:
                return None
            number = (number << 6) | (byte & 0x3F)
        if number < _SHORTEST[tail]:
            return None
        p += 1 + tail
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
    return number, block_size, p + 1 - pos


def _audio_ends(data: bytes, start: int) -> list[int]:
    """Where the last frame could end: the end of the file, or before a tag appended to it.

    ID3v1 (and its "TAG+" extension) and APEv2 are the tags that turn up at the end of FLAC
    files. Each is only a candidate - the last frame's CRC-16 decides (`_last_frame_end`) - so a
    frame whose last bytes happen to spell "TAG" is not cut short by it.
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


#? both sync codes: the fixed-block one and the variable-block one
_SYNCS = (b"\xff\xf8", b"\xff\xf9")


def _last_frame_end(data: bytes, start: int, reach: int, checks: _Checksums) -> int | None:
    """Where the frame at `start` ends if it is the last one; None if it can't be.

    Nothing after the last frame says where it ends, so its CRC-16 does: summed from its start,
    it has to come to zero at exactly one of the places it could end (`_audio_ends`). A place
    further from the start than any frame of the stream can reach (`_reach`) is not one, and is
    ruled out before anything is summed - so a file with megabytes appended costs nothing to
    refuse, and nothing past a frame's reach is ever summed.

    Coming to zero there is not the whole test, though, because the sum carries on unchanged
    through anything appended that sums to zero from scratch - and whatever is let in goes into
    the last MP4 sample, where AVFoundation stops with an error seconds before the end of a song
    it plays through as FLAC. So:
    - The reach is the first guard: with STREAMINFO's largest frame to go by, a last sample
      larger than it is refused whatever it sums to.
    - The sum coming to zero at two of those places - a tag whose own CRC-16 is zero, one in
      65,536 - leaves which of them the audio ends at unknown, and the file is refused.
    - Whole frames each sum to zero. The same pass sums to every sync code in the frame as well -
      of EITHER blocking strategy, since a frame written with the other one sums to zero just the
      same - and one where the sum is zero is a frame's end with another after it: refused.
    - Zero bytes sum to zero (the CRC starts at zero and nothing is XORed at the end). Stripping
      them can't be right - a real frame's CRC-16 ends in a zero byte in one file of 256, and
      that can't be told from a zero appended - but a real frame ends in THREE only when its
      CRC-16 is 0x0000 and the byte before it is zero too, so three are refused. One or two
      appended stay in the last sample, which AVFoundation played through.
    Anything else appended that sums to zero and doesn't start with a sync code still gets in,
    as long as the last sample stays within the reach: one in 65,536 by chance, every time by
    design.
    """
    ends = [end for end in _audio_ends(data, start) if end - start <= reach]
    if not ends:
        return None
    furthest = max(ends)
    syncs = []
    for sync in _SYNCS:
        at = data.find(sync, start + 1, furthest)
        while at >= 0:
            syncs.append(at)
            at = data.find(sync, at + 1, furthest)
    zero = checks.zeros(start, sorted(set(ends + syncs)))
    ends = [end for end in ends if end in zero]
    if not ends:
        return None
    if len(ends) > 1:
        raise Unsupported("the last frame checks out both with the tag after it and without")
    end, = ends
    if any(at in zero and at < end for at in syncs):
        raise Unsupported("what comes after the last frame checks out as more frames")
    if data[end - 3:end] == bytes(3):
        raise Unsupported("the audio ends in zero bytes that may not belong to it")
    return end


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
    used - and so would the real headers after it, were false ones taken for frames k+1 and on as
    well, one after another inside frame k-1's audio. So a header carrying ANY number already
    given to a frame is watched for, not just the last, and when one appears the frame's own
    CRC-16 settles which of the two is real: the frame before them has to checksum to zero from
    its start to the real one (and whatever was taken after a false one was inside that frame).
    Exactly one of them must: neither means the stream isn't what it claims, and both - a chance
    of 1 in 65,536 on top of the false header, unless the file was built that way - leave two
    readings of it. Either is refused. Every such header is charged to FALSE_SYNC_BUDGET, and the
    sums are carried on and remembered (`_Checksums`), so a frame full of copies of a header costs
    one pass over it, not one per copy.

    What bounds that is a frame's reach (`_reach`): no frame is taken that would make the one
    before it longer than any frame of the stream can be, so a header whose number was given
    further back than that can't be the real one - the frame before it would have to be longer
    still - and is passed over without a sum. A real file meets a header carrying some earlier
    number by chance about once in 2^34 bytes (its number only has to be one of the frames
    already found, not the next), which is why it isn't refused; within a frame's reach it is
    checked. The number just given is checked whatever the distance, as it always was: in a file
    as it should be that spans two frames at most.

    (Checksumming every frame would be certain without any of this, but it is a byte-at-a-time
    loop in Python - seconds for an album track - where this is milliseconds.)

    The LAST frame is always checksummed, since nothing after it says where it ends: that is how
    a tag appended to the file is left out, and how a file cut short, or with something else
    appended, is refused (`_last_frame_end`).
    """
    if data[first:first + 1] != b"\xff" or data[first + 1:first + 2] not in (b"\xf8", b"\xf9"):
        raise Unsupported("no audio frame where the metadata ends")
    sync = data[first:first + 2]
    fixed = sync == b"\xff\xf8"
    reach = _reach(info)
    got = _frame_header(data, first, info)
    if got is None or got[0] != 0:
        raise Unsupported("the first audio frame's header isn't valid")
    _, block_size, header_length = got
    starts, blocks, numbers = [first], [block_size], [0]
    search = first + header_length
    budget = FALSE_SYNC_BUDGET[0] + len(data) // FALSE_SYNC_BUDGET[1]
    checks = _Checksums(data)
    while True:
        at = data.find(sync, search)
        if at < 0:
            break
        got = _frame_header(data, at, info)
        #? the number the next frame must carry
        wanted = numbers[-1] + (1 if fixed else blocks[-1])
        if got is not None and got[0] == wanted:
            if at - starts[-1] > reach:
                raise Unsupported(f"a frame would be {at - starts[-1]} bytes, larger than any frame of "
                                  f"this stream can be ({reach})")
            number, block_size, header_length = got
            starts.append(at)
            blocks.append(block_size)
            numbers.append(number)
            search = at + header_length
            continue
        search = at + 1
        budget -= 1
        if budget < 0:
            raise Unsupported("far too many sync codes that start no frame")
        if got is None:
            continue
        number, block_size, header_length = got
        #? a header carrying a number already given to the frame at starts[slot]?
        slot = bisect_left(numbers, number)
        if slot == len(numbers) or numbers[slot] != number or slot == 0:
            #? no - or the first frame's, which is where the metadata ends, so this is audio
            continue
        before = starts[slot - 1]
        if slot < len(starts) - 1 and at - before > reach:
            #? too far on for the frame before that one to end here
            continue
        #? the frame before it ends where the frame given that number was taken to begin - or at
        #? this header instead, and everything taken since then was inside it
        kept = checks.upto(before, starts[slot]) == 0
        moved = checks.upto(before, at) == 0
        if kept and moved:
            raise Unsupported(f"two frames claim to be number {number}, and both check out")
        if moved:
            if at - before > reach:
                raise Unsupported(f"a frame would be {at - before} bytes, larger than any frame of "
                                  f"this stream can be ({reach})")
            del starts[slot:], blocks[slot:], numbers[slot:]
            starts.append(at)
            blocks.append(block_size)
            numbers.append(number)
            search = at + header_length
        elif not kept:
            raise Unsupported(f"two frames claim to be number {number}, and neither checks out")
    shortest = min(_audio_ends(data, starts[-1])) - starts[-1]
    if shortest > reach:
        raise Unsupported(f"the last frame would be {shortest} bytes, larger than any frame of this "
                          f"stream can be ({reach}) - something is appended to the audio, or a "
                          "frame's header is damaged")
    end = _last_frame_end(data, starts[-1], reach, checks)
    if end is None and len(starts) > 1:
        #? the last header found may have been audio data in the real last frame, numbered as
        #? if a frame followed it: then the frame before it checks out to the end of the file
        end = _last_frame_end(data, starts[-2], reach, checks)
        if end is not None:
            del starts[-1], blocks[-1], numbers[-1]
    if end is None:
        raise Unsupported("the last frame's checksum is wrong - the file may be cut short")
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
    stsd = _stsd(info)

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
    minf = _box(b"minf", _SMHD, _DINF, stbl)
    trak = _box(b"trak", tkhd, _box(b"mdia", mdhd, _HDLR, minf))
    return _box(b"moov", mvhd, trak)


#? what both kinds of MP4 say about the track the same way: that it is sound, a sound media
#? header (balance 0), and one data reference - the file itself (flags 1: "the media is in this file")
_HDLR = _full_box(b"hdlr", 0, 0, struct.pack(">I4s12x", 0, b"soun"), b"SoundHandler\x00")
_SMHD = _full_box(b"smhd", 0, 0, bytes(4))
_DINF = _box(b"dinf", _full_box(b"dref", 0, 0, struct.pack(">I", 1), _full_box(b"url ", 0, 1)))


def _stsd(info: StreamInfo) -> bytes:
    """
    The sample description: one 'fLaC' entry carrying STREAMINFO, alone, in a 'dfLa' box - the
    same in the plain MP4 and the fragmented one, which is what lets a player take one song's
    format for the other's.
    """
    dfla = _full_box(b"dfLa", 0, 0, bytes((0x80 | _STREAMINFO,)),
                     len(info.raw).to_bytes(3, "big"), info.raw)
    entry = _box(b"fLaC", bytes(6), struct.pack(">H8xHHHHI", 1, info.channels,
                                                 info.bits_per_sample, 0, 0,
                                                 _entry_rate(info.sample_rate)), dfla)
    return _full_box(b"stsd", 0, 0, struct.pack(">I", 1), entry)


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


# --- the fragmented MP4, for one stream across songs ----------------------------------------
#
# The player's gapless engine plays consecutive FLAC songs as ONE MediaSource stream, and a
# SourceBuffer takes fragmented MP4: an init segment (ftyp + moov, which describes the track and
# holds no samples) and then fragments (moof + mdat), each a run of whole frames with its own
# small table. The layout is the one ffmpeg wrote for the phone lab that played seamlessly on
# James's iPhone - `-movflags frag_keyframe+empty_moov+default_base_moof+skip_trailer
# -frag_duration 1000000` - box for box, without its udta, plus a sidx after the moov: the index
# the page reads to find which bytes hold which second, and never appends.

#? The most fragments one index can list: sidx counts its references in 16 bits. At a second a
#? fragment that is over 18 hours; a song that long plays the ordinary way.
SIDX_MAX_REFERENCES = 0xFFFF

#? ffmpeg's brands for a fragmented file, the lab's exactly
_FMP4_FTYP = _box(b"ftyp", b"iso5", struct.pack(">I", 0x200), b"iso5", b"iso6", b"mp41")

#? tfhd: default-base-is-moof (offsets count from the moof) | a default sample duration | size |
#? flags, as ffmpeg writes it
_TFHD_FLAGS = 0x020038
#? a FLAC frame depends on no other (sample_depends_on 2, and not a non-sync sample): MSE drops
#? frames after any jump - a seek, the next song's init - until it meets one flagged so, and every
#? FLAC frame is one
_SYNC_SAMPLE = 0x02000000
#? trun: a data offset and every sample's size; and every sample's duration when they differ
_TRUN_SIZES = 0x000201
_TRUN_DURATIONS = 0x000100
#? a sidx reference that starts with a sync sample (starts_with_SAP 1, SAP_type 1), as each does
_STARTS_WITH_SAP = 0x90000000


def _init_moov(info: StreamInfo) -> bytes:
    """The fragmented file's moov: the track, with durations of 0 and empty tables - the samples are
    in the fragments - and an mvex saying fragments follow."""
    rate = struct.pack(">I", info.sample_rate)
    zero = struct.pack(">I", 0)
    times = struct.pack(">II", 0, 0)
    mvhd = _full_box(b"mvhd", 0, 0, times, rate, zero, struct.pack(">IH10x", 0x10000, 0x0100),
                     _MATRIX, bytes(24), struct.pack(">I", 2))
    #? flags 3: enabled, in the movie; alternate group 1 - ffmpeg's for an audio track
    tkhd = _full_box(b"tkhd", 0, 3, times, struct.pack(">II", 1, 0), zero,
                     struct.pack(">8xHHH2x", 0, 1, 0x0100), _MATRIX, struct.pack(">II", 0, 0))
    mdhd = _full_box(b"mdhd", 0, 0, times, rate, zero, struct.pack(">HH", _LANGUAGE_UND, 0))
    stbl = _box(b"stbl", _stsd(info), _full_box(b"stts", 0, 0, zero), _full_box(b"stsc", 0, 0, zero),
                _full_box(b"stsz", 0, 0, struct.pack(">II", 0, 0)), _full_box(b"stco", 0, 0, zero))
    minf = _box(b"minf", _SMHD, _DINF, stbl)
    trak = _box(b"trak", tkhd, _box(b"mdia", mdhd, _HDLR, minf))
    #? trex: track 1, the one sample description, and no defaults of its own - each tfhd has them
    mvex = _box(b"mvex", _full_box(b"trex", 0, 0, struct.pack(">IIIII", 1, 1, 0, 0, 0)))
    return _box(b"moov", mvhd, trak, mvex)


def _fragment(sequence: int, before: int, blocks: tuple[int, ...], sizes: list[int]) -> bytes:
    """
    One fragment's moof and the header of the mdat after it, for frames of these block sizes and
    byte sizes, `before` samples into the song. The frames themselves follow the mdat header.
    """
    duration, size = blocks[0], sizes[0]
    if all(block == duration for block in blocks):
        flags, rows = _TRUN_SIZES, struct.pack(f">{len(sizes)}I", *sizes)
    else:
        #? a variable-block stream, or the short last frame of a fixed one
        flags = _TRUN_SIZES | _TRUN_DURATIONS
        rows = b"".join(struct.pack(">II", block, length) for block, length in zip(blocks, sizes))
    mfhd = _full_box(b"mfhd", 0, 0, struct.pack(">I", sequence))
    tfhd = _full_box(b"tfhd", 0, _TFHD_FLAGS, struct.pack(">IIII", 1, duration, size, _SYNC_SAMPLE))
    #? version 1: 64 bits, since samples into a long hi-res song pass 32
    tfdt = _full_box(b"tfdt", 1, 0, struct.pack(">Q", before))

    def moof(offset: int) -> bytes:
        trun = _full_box(b"trun", 0, flags, struct.pack(">Ii", len(blocks), offset), rows)
        return _box(b"moof", mfhd, _box(b"traf", tfhd, tfdt, trun))

    #? the data offset counts from the moof's first byte to the first frame, past the mdat header;
    #? the moof is the same length whatever offset it carries
    length = len(moof(0))
    return moof(length + 8) + struct.pack(">I4s", 8 + sum(sizes), b"mdat")


def fmp4_layout(data: bytes) -> tuple[bytes, list[tuple[bytes, int, int]]]:
    """
    The fragmented MP4 for the FLAC file `data`: the head (ftyp, moov, sidx) and each fragment as
    (its moof and mdat header, start, end) - the fragment on disk is those bytes and then
    data[start:end], the FLAC's own frames, untouched. So a caller writes the head and then, per
    fragment, its header and a slice of the file it already holds, as with mp4_layout().

    The fragments are the same whole-frame groups of about a second as mp4_layout()'s chunks, which
    is also what ffmpeg made the lab's files of (11 frames of 4096 at 44.1 kHz). Byte for byte the
    same every time. Raises NotFlac or Unsupported (both CannotRepackage) for everything
    find_frames() refuses, and Unsupported for a song with more fragments than a sidx can list.
    """
    frames = find_frames(data)
    info = frames.info
    counts = _chunks(frames)
    if len(counts) > SIDX_MAX_REFERENCES:
        raise Unsupported(f"too long for a fragment index: {len(counts)} fragments, where one lists at most "
                          f"{SIDX_MAX_REFERENCES}")
    sizes = frames.sizes()
    bounds = frames.starts + (frames.end,)
    fragments, references, index, before = [], [], 0, 0
    for sequence, count in enumerate(counts, start=1):
        blocks = frames.block_sizes[index:index + count]
        start, end = bounds[index], bounds[index + count]
        header = _fragment(sequence, before, blocks, sizes[index:index + count])
        fragments.append((header, start, end))
        #? referenced_size is 31 bits: a fragment is about a second, and never near 2 GiB under
        #? MAX_INPUT_BYTES
        references.append(struct.pack(">III", len(header) + end - start, sum(blocks), _STARTS_WITH_SAP))
        index += count
        before += sum(blocks)
    #? v0: reference_ID 1, the sample rate as timescale, the first sample at 0, and the first
    #? fragment straight after this box (first_offset 0)
    sidx = _full_box(b"sidx", 0, 0, struct.pack(">IIIIHH", 1, info.sample_rate, 0, 0, 0, len(references)),
                     *references)
    return b"".join((_FMP4_FTYP, _init_moov(info), sidx)), fragments


def flac_to_fmp4(data: bytes) -> bytes:
    """The FLAC file `data` as a fragmented MP4 of the same frames - see fmp4_layout()."""
    if not isinstance(data, bytes):
        data = bytes(data)
    head, fragments = fmp4_layout(data)
    view = memoryview(data)
    return b"".join([head, *(part for header, start, end in fragments for part in (header, view[start:end]))])
