"""
FLAC repackaged as an MP4 of the same frames (src/flac_mp4.py) - the fix for Safari's seek bar.

Every FLAC here is made by the small encoder below, which writes VERBATIM subframes: the samples
as they are, which is valid FLAC and lets a test put any bytes it likes inside a frame's audio -
a copy of the next frame's header, the worst false sync there can be. The encoder knows where it
put every frame, so the MP4's tables are checked against the truth rather than against what the
module itself found. No binary fixtures are committed and nothing here needs ffmpeg or flac;
the few tests that use them (decoding both files to PCM and comparing) skip when they're absent.
"""

import hashlib
import random
import shutil
import struct
import subprocess

import pytest

from src import flac_mp4
from src.flac_mp4 import CannotRepackage, NotFlac, Unsupported, flac_to_mp4

# --- a FLAC encoder, verbatim subframes only -------------------------------------------------

BLOCK_CODES = {192: 1, 576: 2, 1152: 3, 2304: 4, 4608: 5, 256: 8, 512: 9, 1024: 10, 2048: 11,
               4096: 12, 8192: 13, 16384: 14, 32768: 15}
RATE_CODES = {88200: 1, 176400: 2, 192000: 3, 8000: 4, 16000: 5, 22050: 6, 24000: 7, 32000: 8,
              44100: 9, 48000: 10, 96000: 11}
SIZE_CODES = {8: 1, 12: 2, 16: 4, 20: 5, 24: 6, 32: 7}


def crc_bitwise(data, poly, width):
    """A CRC the long way, bit by bit: an independent check on the module's own tables."""
    top, mask, crc = 1 << (width - 1), (1 << width) - 1, 0
    for byte in data:
        crc ^= byte << (width - 8)
        for _ in range(8):
            crc = ((crc << 1) ^ poly) & mask if crc & top else (crc << 1) & mask
    return crc


def crc8(data):
    return crc_bitwise(data, 0x07, 8)


#? the bitwise CRC-16 is too slow for whole frames, so it builds a table once
CRC16_TABLE = [crc_bitwise(bytes([b]), 0x8005, 16) for b in range(256)]


def crc16(data, crc=0):
    for byte in data:
        crc = ((crc << 8) & 0xFFFF) ^ CRC16_TABLE[(crc >> 8) ^ byte]
    return crc


def coded(n):
    """A frame or sample number as FLAC codes it."""
    if n < 0x80:
        return bytes([n])
    extra = next(e for e, limit in enumerate([0, 1 << 11, 1 << 16, 1 << 21, 1 << 26, 1 << 31, 1 << 36]) if n < limit)
    out = [0x80 | ((n >> (6 * i)) & 0x3F) for i in range(extra - 1, -1, -1)]
    return bytes([((0xFF << (7 - extra)) & 0xFF) | (n >> (6 * extra))] + out)


def frame_header(number, block, *, rate, channels, bps, variable, rate_style):
    head = bytearray([0xFF, 0xF9 if variable else 0xF8])
    if block in BLOCK_CODES:
        block_code, block_tail = BLOCK_CODES[block], b""
    elif block <= 256:
        block_code, block_tail = 6, bytes([block - 1])
    else:
        block_code, block_tail = 7, struct.pack(">H", block - 1)
    if rate_style == "table":
        rate_code, rate_tail = RATE_CODES.get(rate, 0), b""
    elif rate_style == "khz":
        rate_code, rate_tail = 12, bytes([rate // 1000])
    elif rate_style == "hz":
        rate_code, rate_tail = 13, struct.pack(">H", rate)
    elif rate_style == "tens":
        rate_code, rate_tail = 14, struct.pack(">H", rate // 10)
    else:
        rate_code, rate_tail = 0, b""       # "streaminfo": read the rate from there
    head.append((block_code << 4) | rate_code)
    head.append(((channels - 1) << 4) | (SIZE_CODES.get(bps, 0) << 1))
    head += coded(number) + block_tail + rate_tail
    head.append(crc8(head))
    return bytes(head)


def encode(*, rate=44100, channels=2, bps=16, blocks=(4096,) * 4 + (1000,), variable=False,
           rate_style="table", seed=1, plant=None, total=None, id3=b"", trailer=b""):
    """A FLAC file, and the frames in it as (offset, bytes, block size).

    `plant` maps a frame index to (byte offset into its first channel's samples, bytes) - or to a
    function of the list of every frame's header that returns them, to copy a real header in.
    """
    rng = random.Random(seed)
    width = bps // 8
    headers, number = [], 0
    for block in blocks:
        headers.append(frame_header(number, block, rate=rate, channels=channels, bps=bps,
                                    variable=variable, rate_style=rate_style))
        number += block if variable else 1
    frames, pcm = [], bytearray()
    for index, (block, header) in enumerate(zip(blocks, headers)):
        samples = [[rng.randrange(-(1 << (bps - 1)), 1 << (bps - 1)) for _ in range(block)]
                   for _ in range(channels)]
        body = bytearray()
        for channel in samples:
            #? subframe header 0b0_000001_0: verbatim, no wasted bits
            body.append(0x02)
            body += b"".join(s.to_bytes(width, "big", signed=True) for s in channel)
        if plant and index in plant:
            at, what = plant[index]
            what = what(headers) if callable(what) else what
            body[1 + at:1 + at + len(what)] = what
        frame = header + bytes(body)
        frame += struct.pack(">H", crc16(frame))
        frames.append(frame)
        #? what STREAMINFO's MD5 is taken over: interleaved, little-endian - read back from the
        #? planted body so the checksum matches what the file really holds
        values = [[int.from_bytes(body[at:at + width], "big", signed=True)
                   for at in range(1 + c * (1 + block * width), (c + 1) * (1 + block * width), width)]
                  for c in range(channels)]
        for i in range(block):
            for c in range(channels):
                pcm += values[c][i].to_bytes(width, "little", signed=True)
    sizes = [len(f) for f in frames]
    min_block = min(blocks[:-1]) if len(blocks) > 1 else blocks[0]
    streaminfo = struct.pack(">HH", min_block, max(blocks))
    streaminfo += min(sizes).to_bytes(3, "big") + max(sizes).to_bytes(3, "big")
    total = sum(blocks) if total is None else total
    streaminfo += ((rate << 44) | ((channels - 1) << 41) | ((bps - 1) << 36) | total).to_bytes(8, "big")
    streaminfo += hashlib.md5(pcm).digest()
    vendor = b"deadwax test encoder"
    comment = struct.pack("<I", len(vendor)) + vendor + struct.pack("<I", 1) + struct.pack("<I", 9) + b"TITLE=One"
    seektable = struct.pack(">QQH", 0xFFFFFFFFFFFFFFFF, 0, 0)
    blocks_meta = [(0, streaminfo), (3, seektable), (4, comment), (1, bytes(64))]
    out = bytearray(id3 + b"fLaC")
    for i, (kind, data) in enumerate(blocks_meta):
        out.append(kind | (0x80 if i == len(blocks_meta) - 1 else 0))
        out += len(data).to_bytes(3, "big") + data
    offsets = []
    for frame, block in zip(frames, blocks):
        offsets.append((len(out), frame, block))
        out += frame
    return bytes(out) + trailer, offsets


def id3v2(size=300):
    return b"ID3\x04\x00\x00" + bytes([(size >> 21) & 0x7F, (size >> 14) & 0x7F, (size >> 7) & 0x7F, size & 0x7F]) + bytes(size)


# --- an MP4 reader -----------------------------------------------------------------------

CONTAINERS = {b"moov", b"trak", b"mdia", b"minf", b"stbl", b"dinf"}


def boxes(data, start=0, end=None):
    """[(type, body start, body end)] of the boxes between start and end."""
    end = len(data) if end is None else end
    found, pos = [], start
    while pos < end:
        size, kind = struct.unpack(">I4s", data[pos:pos + 8])
        header = 8
        if size == 1:
            size, header = struct.unpack(">Q", data[pos + 8:pos + 16])[0], 16
        assert size >= header and pos + size <= end, f"box {kind} runs past its parent"
        found.append((kind, pos + header, pos + size))
        pos += size
    assert pos == end
    return found


def box(data, *path):
    """The body of the box at `path` (moov, trak, ...)."""
    start, end = 0, len(data)
    for kind in path:
        matches = [(s, e) for k, s, e in boxes(data, start, end) if k == kind]
        assert len(matches) == 1, f"{len(matches)} {kind} boxes"
        start, end = matches[0]
    return data[start:end]


def read_mp4(data):
    """Everything a player would take from the file, and the audio of each sample."""
    top = [k for k, _, _ in boxes(data)]
    assert top == [b"ftyp", b"moov", b"mdat"], top
    stbl = (b"moov", b"trak", b"mdia", b"minf", b"stbl")
    mvhd = box(data, b"moov", b"mvhd")
    mdhd = box(data, b"moov", b"trak", b"mdia", b"mdhd")
    if mdhd[0] == 1:
        timescale, duration = struct.unpack(">IQ", mdhd[20:32])
        movie_scale, movie_duration = struct.unpack(">IQ", mvhd[20:32])
    else:
        timescale, duration = struct.unpack(">II", mdhd[12:20])
        movie_scale, movie_duration = struct.unpack(">II", mvhd[12:20])
    stsd = box(data, *stbl, b"stsd")
    assert struct.unpack(">I", stsd[4:8])[0] == 1
    entry = stsd[8:]
    entry_size, entry_kind = struct.unpack(">I4s", entry[:8])
    assert entry_kind == b"fLaC" and entry_size == len(entry)
    reference, = struct.unpack(">H", entry[14:16])
    channels, sample_size, _, _, entry_rate = struct.unpack(">HHHHI", entry[24:36])
    (dfla_kind, dfla_start, dfla_end), = boxes(entry, 36)
    dfla = entry[dfla_start:dfla_end]
    stts = box(data, *stbl, b"stts")
    durations = []
    for i in range(struct.unpack(">I", stts[4:8])[0]):
        count, delta = struct.unpack(">II", stts[8 + 8 * i:16 + 8 * i])
        durations += [delta] * count
    stsz = box(data, *stbl, b"stsz")
    fixed, count = struct.unpack(">II", stsz[4:12])
    sizes = [fixed] * count if fixed else list(struct.unpack(f">{count}I", stsz[12:12 + 4 * count]))
    table = [k for k, _, _ in boxes(data, *_body(data, *stbl))]
    wide = b"co64" in table
    stco = box(data, *stbl, b"co64" if wide else b"stco")
    chunks = struct.unpack(">I", stco[4:8])[0]
    offsets = list(struct.unpack(f">{chunks}{'Q' if wide else 'I'}", stco[8:]))
    stsc = box(data, *stbl, b"stsc")
    rows = [struct.unpack(">III", stsc[8 + 12 * i:20 + 12 * i]) for i in range(struct.unpack(">I", stsc[4:8])[0])]
    per_chunk = []
    for i, (first, per, description) in enumerate(rows):
        assert description == 1
        last = rows[i + 1][0] if i + 1 < len(rows) else chunks + 1
        per_chunk += [per] * (last - first)
    assert len(per_chunk) == chunks and sum(per_chunk) == count
    samples, sample = [], 0
    for offset, per in zip(offsets, per_chunk):
        for _ in range(per):
            samples.append(data[offset:offset + sizes[sample]])
            offset += sizes[sample]
            sample += 1
    return {
        "timescale": timescale, "duration": duration, "movie": (movie_scale, movie_duration),
        "handler": box(data, b"moov", b"trak", b"mdia", b"hdlr")[8:12], "reference": reference,
        "channels": channels, "sample_size": sample_size, "entry_rate": entry_rate,
        "dfla": (dfla_kind, dfla), "durations": durations, "sizes": sizes, "samples": samples,
        "per_chunk": per_chunk, "mdat": box(data, b"mdat"), "chunk_table": b"co64" if wide else b"stco",
    }


def _body(data, *path):
    start, end = 0, len(data)
    for kind in path:
        (start, end), = [(s, e) for k, s, e in boxes(data, start, end) if k == kind]
    return start, end


def assert_same_frames(mp4, flac, frames):
    """The MP4 holds exactly these frames, in order, each one sample, timed by its block size."""
    got = read_mp4(mp4)
    assert got["samples"] == [f for _, f, _ in frames]
    assert got["sizes"] == [len(f) for _, f, _ in frames]
    assert got["durations"] == [b for _, _, b in frames]
    assert got["duration"] == sum(b for _, _, b in frames)
    assert got["mdat"] == b"".join(f for _, f, _ in frames)
    #? the audio in the MP4 is the FLAC's, byte for byte, from its first frame to its last
    first, last = frames[0][0], frames[-1][0] + len(frames[-1][1])
    assert got["mdat"] == flac[first:last]
    return got


# --- the tests -------------------------------------------------------------------------------

def test_a_cd_stream_becomes_an_mp4_of_the_same_frames():
    flac, frames = encode(blocks=(4096,) * 30 + (1234,))
    mp4 = flac_to_mp4(flac)
    got = assert_same_frames(mp4, flac, frames)
    assert got["timescale"] == 44100
    assert got["movie"] == (44100, 30 * 4096 + 1234)
    assert got["handler"] == b"soun"
    assert got["reference"] == 1
    assert (got["channels"], got["sample_size"], got["entry_rate"]) == (2, 16, 44100 << 16)
    assert box(mp4, b"ftyp")[:4] == b"isom"


def test_dfla_carries_streaminfo_alone_marked_as_the_last_block():
    """isoflac.txt: a FullBox v0, STREAMINFO first; ours holds nothing else, so its flag is set."""
    flac, _ = encode()
    kind, dfla = read_mp4(flac_to_mp4(flac))["dfla"]
    assert kind == b"dfLa"
    assert dfla[:4] == bytes(4)                    # version 0, flags 0
    assert dfla[4] == 0x80                         # last-metadata-block flag, type 0 (STREAMINFO)
    assert dfla[5:8] == (34).to_bytes(3, "big")
    streaminfo_at = 4 + 4                          # "fLaC", then the block's own header
    assert dfla[8:] == flac[streaminfo_at:streaminfo_at + 34]


def test_samples_are_chunked_about_a_second_at_a_time():
    flac, _ = encode(blocks=(4096,) * 30 + (1234,))
    #? 11 frames of 4096 is the first run past 44100 samples
    assert read_mp4(flac_to_mp4(flac))["per_chunk"] == [11, 11, 9]


def test_an_id3_tag_in_front_is_skipped_and_changes_nothing():
    flac, frames = encode()
    tagged, _ = encode(id3=id3v2())
    assert flac_to_mp4(tagged) == flac_to_mp4(flac)
    assert_same_frames(flac_to_mp4(tagged), flac, frames)


def test_the_output_is_the_same_every_time():
    """No timestamps: the same file makes the same bytes, which is what lets a copy be cached."""
    flac, _ = encode()
    assert flac_to_mp4(flac) == flac_to_mp4(bytearray(flac))


def next_header(index):
    return lambda headers: headers[index + 1]


def test_a_copy_of_the_next_frames_header_inside_a_frame_does_not_split_it():
    """The worst false sync there is: the real next header, byte for byte, CRC-8 and all.

    It is found first and taken for frame 4; then the real frame 4 turns up carrying the same
    number, and frame 3's CRC-16 says which of the two it ends at.
    """
    flac, frames = encode(blocks=(4096,) * 8, plant={3: (1000, next_header(3))})
    header = frame_header(4, 4096, rate=44100, channels=2, bps=16, variable=False, rate_style="table")
    assert frames[4][1].startswith(header) and flac.count(header) == 2   # the plant is a second copy
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_false_syncs_of_every_other_kind_are_passed_over():
    real = frame_header(2, 4096, rate=44100, channels=2, bps=16, variable=False, rate_style="table")
    bad_crc = real[:-1] + bytes([real[-1] ^ 0x5A])
    wrong_number = frame_header(7, 4096, rate=44100, channels=2, bps=16, variable=False, rate_style="table")
    wrong_rate = frame_header(2, 4096, rate=48000, channels=2, bps=16, variable=False, rate_style="table")
    flac, frames = encode(blocks=(4096,) * 5, plant={
        1: (10, bad_crc + b"\xff\xf8" + wrong_number + wrong_rate + b"\xff\xf9\xc9\x18\x02"),
    })
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_a_copy_of_the_first_frames_header_inside_it_is_ignored():
    flac, frames = encode(blocks=(4096,) * 4, plant={0: (500, lambda headers: headers[0])})
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_a_header_numbered_past_the_end_inside_the_last_frame_is_not_a_frame():
    """Nothing comes after it to show it up, so the end of the file does: it can't checksum."""
    extra = frame_header(4, 4096, rate=44100, channels=2, bps=16, variable=False, rate_style="table")
    flac, frames = encode(blocks=(4096,) * 4, plant={3: (2000, extra)})
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_a_false_header_before_the_last_frame_is_resolved_too():
    flac, frames = encode(blocks=(4096,) * 4 + (100,), plant={3: (700, next_header(3))})
    assert_same_frames(flac_to_mp4(flac), flac, frames)


CD = flac_mp4.StreamInfo(raw=bytes(34), min_block=4096, max_block=4096, sample_rate=44100,
                         channels=2, bits_per_sample=16, total_samples=0)
#? frame 5 of that stream: 4096 samples, 44.1 kHz, left/side stereo, 16-bit
GOOD = [0xFF, 0xF8, 0xC9, 0x88, 5]


def header_check(head, numbers=(5,), fix_crc=True):
    """What `_frame_header` makes of `head` (with its CRC-8 made right unless told otherwise)."""
    data = bytes(head) + (bytes([crc8(bytes(head))]) if fix_crc else b"") + bytes(20)
    return flac_mp4._frame_header(data, 0, CD, tuple(coded(n) for n in numbers))


def test_a_good_header_is_read():
    assert header_check(GOOD) == (0, 4096, 6)
    assert header_check(GOOD, numbers=(6, 5)) == (1, 4096, 6)
    assert header_check([0xFF, 0xF8, 0x79, 0x88, 5, 0x0F, 0xFF]) == (0, 4096, 8)   # a 16-bit tail


@pytest.mark.parametrize("head, why", [
    ([0xFF, 0xF8, 0xC9, 0x08, 5], "one channel in a stereo stream"),
    ([0xFF, 0xF8, 0xC9, 0xB8, 5], "a reserved channel assignment"),
    ([0xFF, 0xF8, 0xC9, 0x8C, 5], "24-bit in a 16-bit stream"),
    ([0xFF, 0xF8, 0xC9, 0x86, 5], "the reserved sample size"),
    ([0xFF, 0xF8, 0xC9, 0x89, 5], "the reserved bit after the sample size"),
    ([0xFF, 0xF8, 0xCA, 0x88, 5], "48 kHz in a 44.1 kHz stream"),
    ([0xFF, 0xF8, 0xCD, 0x88, 5, 0xBB, 0x80], "48000 Hz written out in a 44.1 kHz stream"),
    ([0xFF, 0xF8, 0xCF, 0x88, 5], "the invalid rate code"),
    ([0xFF, 0xF8, 0x09, 0x88, 5], "the reserved block size"),
    ([0xFF, 0xF8, 0xD9, 0x88, 5], "8192 samples, past STREAMINFO's largest"),
    ([0xFF, 0xF8, 0xC9, 0x88, 6], "the wrong frame number"),
    ([0xFF, 0xF8, 0xC9, 0x88, 0xC0, 0x85], "the right number, written the long way"),
])
def test_a_header_wrong_in_any_one_field_is_not_a_frame(head, why):
    assert header_check(head) is None, why


def test_a_header_with_a_bad_crc_is_not_a_frame():
    good = bytes(GOOD) + bytes([crc8(bytes(GOOD))])
    assert header_check(list(good), fix_crc=False) == (0, 4096, 6)
    assert header_check(list(good[:-1]) + [good[-1] ^ 1], fix_crc=False) is None


def test_a_header_cut_off_by_the_end_of_the_file_is_not_a_frame():
    head = bytes([0xFF, 0xF8, 0x79, 0x88, 5, 0x0F])
    assert flac_mp4._frame_header(head, 0, CD, (coded(5),)) is None


def test_a_file_full_of_sync_codes_is_refused_rather_than_searched_for_ever():
    """Audio that is nothing but 0xFFF8 (-8, stored verbatim) has a false sync every two bytes."""
    noise = {i: (0, b"\xff\xf8" * 4096) for i in range(5)}
    flac, _ = encode(blocks=(4096,) * 6, plant=noise)
    assert flac.count(b"\xff\xf8") > flac_mp4.FALSE_SYNC_BUDGET[0] + len(flac) // flac_mp4.FALSE_SYNC_BUDGET[1]
    with pytest.raises(Unsupported, match="sync codes"):
        flac_to_mp4(flac)
    #? under the budget, the same kind of audio is only slow to search, not refused
    flac, frames = encode(blocks=(4096,) * 4, plant={1: (0, b"\xff\xf8" * 4096)})
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_two_false_headers_in_a_row_are_refused_rather_than_guessed():
    """Copies of frames 4 AND 5 inside frame 3: no reading of it checks out, so no MP4 at all."""
    flac, _ = encode(blocks=(4096,) * 8, plant={3: (1000, lambda h: h[4] + bytes(40) + h[5])})
    with pytest.raises(Unsupported):
        flac_to_mp4(flac)


def two_readings():
    """A valid FLAC with a copy of frame 2's header inside frame 1, just after two bytes that make
    frame 1's checksum come to zero there - so frame 1 checks out ending at the copy AND at the
    real frame 2. Returns the file, its frames, and where the copy is."""
    blocks, at = (4096,) * 6 + (1000,), 2000
    flac, frames = encode(blocks=blocks, plant={1: (at, lambda h: bytes(2) + h[2])})
    start = frames[1][0]
    copy = start + 6 + 1 + at + 2          # frame 1's header, its first subframe's, the two bytes
    crc = struct.pack(">H", crc16(flac[start:copy - 2]))
    flac, frames = encode(blocks=blocks, plant={1: (at, lambda h: crc + h[2])})
    return flac, frames, copy


def test_a_copy_of_the_next_header_where_both_readings_check_out_is_refused():
    """The first one found used to be kept, splitting frame 1 in two with no error: an MP4
    AVFoundation couldn't decode, of a file that plays as FLAC."""
    flac, frames, copy = two_readings()
    assert crc16(flac[frames[1][0]:copy]) == 0 and flac[copy:copy + 6] == frames[2][1][:6]
    with pytest.raises(Unsupported, match="both check out"):
        flac_to_mp4(flac)


def copies_of_its_own_header(copies, frame=1):
    """Frame `frame`'s audio starting with `copies` copies of its own header: each one a header
    carrying the number just used - and still a valid FLAC."""
    return encode(blocks=(4096,) * 4, plant={frame: (0, lambda h: h[frame] * copies)})


@pytest.mark.parametrize("frame", [0, 1])
def test_headers_repeating_the_number_just_used_are_charged_as_false_syncs(monkeypatch, frame):
    flac, frames = copies_of_its_own_header(1000, frame)
    assert_same_frames(flac_to_mp4(flac), flac, frames)
    monkeypatch.setattr(flac_mp4, "FALSE_SYNC_BUDGET", (500, 1 << 40))
    with pytest.raises(Unsupported, match="sync codes"):
        flac_to_mp4(flac)


def test_a_frame_full_of_copies_of_a_header_is_checksummed_once_not_once_a_copy(monkeypatch):
    """Each copy used to sum the whole frame before it again: a thousand copies of one header in a
    32768-sample frame took nine seconds, and a frame packed with them over three minutes."""
    flac, frames = copies_of_its_own_header(1000)
    summed, crc16_of = [], flac_mp4._crc16
    monkeypatch.setattr(flac_mp4, "_crc16", lambda data, crc=0: summed.append(len(data)) or crc16_of(data, crc))
    assert_same_frames(flac_to_mp4(flac), flac, frames)
    #? frame 0 once, frame 1 up to its last copy (its header, its subframe's, 999 copies more), then
    #? the last frame - where the old way summed frame 0 a thousand times, 16 MB
    assert sum(summed) <= len(frames[0][1]) + 7 + 6 * 999 + len(frames[-1][1])


def test_checksumming_is_bounded_and_refused_past_the_bound(monkeypatch):
    """A file as it should be sums its last frame and nothing else, which the bound's floor covers
    many times over."""
    flac, frames = encode()
    monkeypatch.setattr(flac_mp4, "CHECKSUM_BUDGET", (len(frames[-1][1]), 0))
    assert_same_frames(flac_to_mp4(flac), flac, frames)
    monkeypatch.setattr(flac_mp4, "CHECKSUM_BUDGET", (len(frames[-1][1]) - 1, 0))
    with pytest.raises(Unsupported, match="checksumming"):
        flac_to_mp4(flac)


@pytest.mark.parametrize("cut", ["in the last frame", "in a middle frame", "after the metadata", "in the metadata"])
def test_a_truncated_file_is_refused(cut):
    flac, frames = encode(blocks=(4096,) * 6 + (500,))
    at = {
        "in the last frame": frames[-1][0] + 300,
        "in a middle frame": frames[3][0] + 5000,
        "after the metadata": frames[0][0],
        "in the metadata": 30,
    }[cut]
    with pytest.raises(Unsupported):
        flac_to_mp4(flac[:at])


def test_a_file_cut_exactly_between_frames_is_refused_when_streaminfo_knows_the_length():
    flac, frames = encode(blocks=(4096,) * 6)
    with pytest.raises(Unsupported, match="STREAMINFO says"):
        flac_to_mp4(flac[:frames[4][0]])


def test_an_unknown_length_is_taken_from_the_frames():
    flac, frames = encode(blocks=(4096,) * 6 + (10,), total=0)
    assert_same_frames(flac_to_mp4(flac), flac, frames)


@pytest.mark.parametrize("data", [
    b"",
    b"RIFF\x24\x00\x00\x00WAVEfmt ",
    b"OggS" + bytes(60),
    id3v2(100) + b"\xff\xfb\x90\x00" + bytes(400),       # an MP3 behind its tag
    b"ID3\x04\x00\x00\x80\x80\x80\x80",                  # an ID3 header with a size that isn't syncsafe
    bytes(range(256)) * 4,
], ids=["empty", "wav", "ogg", "mp3 behind id3", "bad id3 size", "noise"])
def test_something_that_isnt_flac_is_said_to_be_so(data):
    with pytest.raises(NotFlac):
        flac_to_mp4(data)


def test_both_refusals_are_value_errors_the_caller_can_catch_as_one():
    assert issubclass(NotFlac, CannotRepackage) and issubclass(Unsupported, CannotRepackage)
    assert issubclass(CannotRepackage, ValueError)


@pytest.mark.parametrize("rate, entry", [
    (96000, 48000), (192000, 48000), (88200, 44100), (176400, 44100), (384000, 48000),
    (65535, 65535), (70000, 35000), (100001, 65535),
])
def test_rates_past_16_bits_go_in_the_sample_entry_as_isoflac_says(rate, entry):
    assert flac_mp4._entry_rate(rate) == entry << 16


@pytest.mark.parametrize("rate", [96000, 192000])
def test_hi_res_keeps_its_real_rate_in_the_timescale_and_streaminfo(rate):
    flac, frames = encode(rate=rate, bps=24, blocks=(4096,) * 6 + (77,))
    got = assert_same_frames(flac_to_mp4(flac), flac, frames)
    assert got["timescale"] == rate
    assert got["entry_rate"] == 48000 << 16
    assert got["sample_size"] == 24
    assert int.from_bytes(got["dfla"][1][8 + 10:8 + 18], "big") >> 44 == rate


@pytest.mark.parametrize("channels, bps", [(1, 16), (6, 16), (8, 24), (1, 8), (2, 32)])
def test_channel_counts_and_sample_sizes_come_through(channels, bps):
    flac, frames = encode(rate=48000, channels=channels, bps=bps, blocks=(1152,) * 5 + (300,))
    got = assert_same_frames(flac_to_mp4(flac), flac, frames)
    assert (got["channels"], got["sample_size"]) == (channels, bps)


@pytest.mark.parametrize("style, rate", [("streaminfo", 44100), ("khz", 11000), ("hz", 22000), ("tens", 88200)])
def test_every_way_a_frame_header_can_give_its_rate_is_read(style, rate):
    flac, frames = encode(rate=rate, rate_style=style, blocks=(4096,) * 3 + (99,))
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_a_variable_block_size_stream_is_numbered_by_sample():
    blocks = (1152, 4608, 576, 4096, 192, 2000, 16, 4608, 4608, 4608, 333)
    flac, frames = encode(blocks=blocks, variable=True)
    got = assert_same_frames(flac_to_mp4(flac), flac, frames)
    assert got["durations"] == list(blocks)


def test_sample_numbers_that_take_four_bytes_to_write():
    flac, frames = encode(blocks=(4096,) * 20 + (5,), variable=True, channels=1, rate=8000,
                          plant={17: (900, next_header(17))})
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_frame_numbers_past_the_one_and_two_byte_codings():
    """Frames 128 and 2048 are where the number's coding grows a byte."""
    flac, frames = encode(rate=8000, channels=1, bps=8, blocks=(16,) * 2100 + (3,),
                          plant={127: (2, next_header(127)), 2047: (1, next_header(2047))})
    assert_same_frames(flac_to_mp4(flac), flac, frames)


@pytest.mark.parametrize("trailer", [
    b"TAG" + bytes(125),                                        # ID3v1
    b"TAG+" + bytes(223) + b"TAG" + bytes(125),                 # ID3v1 with its extension
    b"APETAGEX" + struct.pack("<IIII8x", 2000, 32, 0, 0),       # an APEv2 footer, nothing else
    (b"APETAGEX" + struct.pack("<IIII8x", 2000, 64, 0, 0xA0000000) + bytes(32)
     + b"APETAGEX" + struct.pack("<IIII8x", 2000, 64, 0, 0x80000000) + b"TAG" + bytes(125)),
], ids=["id3v1", "id3v1 extended", "ape footer", "ape with header, then id3v1"])
def test_a_tag_after_the_audio_is_left_out(trailer):
    flac, frames = encode(trailer=trailer)
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_audio_that_happens_to_spell_tag_is_not_cut_off():
    flac, frames = encode(blocks=(4096,) * 3 + (200,))
    last = frames[-1][0] + len(frames[-1][1])
    at = last - 128 - (frames[-1][0] + len(frame_header(3, 200, rate=44100, channels=2, bps=16,
                                                                 variable=False, rate_style="table")) + 1)
    flac, frames = encode(blocks=(4096,) * 3 + (200,), plant={3: (at, b"TAG")})
    assert flac[len(flac) - 128:len(flac) - 125] == b"TAG"
    assert_same_frames(flac_to_mp4(flac), flac, frames)


@pytest.mark.parametrize("zeros", [1, 2])
def test_one_or_two_zero_bytes_after_the_audio_stay_in_the_last_sample(zeros):
    """A frame's checksum starts at zero and ends with nothing XORed in, so it comes to zero again
    after every zero byte appended. One or two can't be told from a last frame whose own CRC-16
    ends in zero, which one file in 256 has, so they are kept - AVFoundation played such an MP4
    to its end."""
    flac, frames = encode()
    assert flac[-1] != 0
    got = read_mp4(flac_to_mp4(flac + bytes(zeros)))
    assert got["samples"][:-1] == [f for _, f, _ in frames[:-1]]
    assert got["samples"][-1] == frames[-1][1] + bytes(zeros)


@pytest.mark.parametrize("trailer", [bytes(3), bytes(16), bytes(4096), bytes(16) + b"TAG" + bytes(125)],
                         ids=["3", "16", "4096", "16 before an id3v1 tag"])
def test_three_or_more_zero_bytes_after_the_audio_are_refused(trailer):
    """In the last MP4 sample, 16 zeros made AVFoundation stop with an error over two seconds
    before the end of a song it plays to the end as FLAC. A real frame ends in three zeros only
    when its CRC-16 is 0x0000 and the byte before it is zero too."""
    flac, _ = encode()
    with pytest.raises(Unsupported, match="zero bytes"):
        flac_to_mp4(flac + trailer)


def ending_in(footer, after=b""):
    """A FLAC whose last frame ends in `after` and then the CRC-16 `footer`, and its frames.

    The two sample bytes before `after` are solved for: CRC-16 is linear, so exactly one pair
    gives any footer.
    """
    kw = dict(rate=8000, channels=1, bps=8, blocks=(16,) * 3 + (8,))
    at = 8 - 2 - len(after)
    flac, frames = encode(**kw, plant={3: (at, bytes(2) + after)})
    frame = frames[-1][1]
    before = crc16(frame[:len(frame) - 4 - len(after)])
    pair = next(bytes((p, q)) for p in range(256) for q in range(256)
                if crc16(bytes((p, q)) + after, before) == footer)
    flac, frames = encode(**kw, plant={3: (at, pair + after)})
    assert flac.endswith(after + struct.pack(">H", footer))
    return flac, frames


@pytest.mark.parametrize("footer, after", [(0x1200, b""), (0x0000, b"\x01")], ids=["one zero", "two zeros"])
def test_a_last_frame_whose_own_checksum_ends_in_zeros_is_kept_whole(footer, after):
    flac, frames = ending_in(footer, after)
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_the_price_a_last_frame_ending_in_three_zeros_of_its_own_is_sent_as_flac():
    flac, _ = ending_in(0x0000, b"\x00")
    with pytest.raises(Unsupported, match="zero bytes"):
        flac_to_mp4(flac)


def test_a_tag_that_checks_out_as_audio_as_well_is_refused():
    """An ID3v1 tag whose own CRC-16 is zero (one in 65,536) leaves the last frame checking out
    both before it and at the end of the file. The longer used to be taken, tag and all."""
    body = b"TAG" + bytes(123)
    flac, frames = encode(trailer=body + struct.pack(">H", crc16(body)))
    assert crc16(flac[frames[-1][0]:]) == 0
    with pytest.raises(Unsupported, match="with the tag after it and without"):
        flac_to_mp4(flac)


@pytest.mark.parametrize("what", ["its first three frames again", "a frame of another stream", "its last frame again"])
def test_whole_frames_after_the_last_are_refused(what):
    """Each checks out on its own, so the last frame's checksum comes to zero at the end of the
    file as well, and the MP4's last sample would have held them all."""
    flac, frames = encode()
    extra = {
        "its first three frames again": lambda: b"".join(f for _, f, _ in frames[:3]),
        "a frame of another stream": lambda: encode(rate=48000, seed=5)[1][1][1],
        "its last frame again": lambda: frames[-1][1],
    }[what]()
    #? the last frame again carries the last number again: two readings, both checking out
    with pytest.raises(Unsupported, match="both check out" if what == "its last frame again" else "more frames"):
        flac_to_mp4(flac + extra)


def test_streaminfo_must_come_first():
    flac, _ = encode()
    moved = flac[:4] + bytes([4]) + flac[5:]        # call the first block a VORBIS_COMMENT
    with pytest.raises(Unsupported, match="STREAMINFO"):
        flac_to_mp4(moved)


def test_a_fixed_block_size_stream_whose_frames_change_size_is_refused():
    flac, _ = encode(blocks=(4096, 4096, 1024, 4096, 100))
    with pytest.raises(Unsupported, match="change size"):
        flac_to_mp4(flac)


def test_the_size_limit_is_enforced(monkeypatch):
    flac, _ = encode()
    monkeypatch.setattr(flac_mp4, "MAX_INPUT_BYTES", len(flac) - 1)
    with pytest.raises(Unsupported, match="larger than"):
        flac_to_mp4(flac)


def test_offsets_past_4_gib_use_co64():
    flac, _ = encode(blocks=(4096,) * 30)
    frames = flac_mp4.find_frames(flac)
    small, large = flac_mp4._moov(frames, 1000), flac_mp4._moov(frames, (1 << 32) + 1000)
    shape = [k for k, _, _ in boxes(large, *_body(large, b"moov", b"trak", b"mdia", b"minf", b"stbl"))]
    assert shape[-1] == b"co64"
    co64 = box(large, b"moov", b"trak", b"mdia", b"minf", b"stbl", b"co64")
    stco = box(small, b"moov", b"trak", b"mdia", b"minf", b"stbl", b"stco")
    count = struct.unpack(">I", stco[4:8])[0]
    assert [o - (1 << 32) for o in struct.unpack(f">{count}Q", co64[8:])] == list(struct.unpack(f">{count}I", stco[8:]))


def test_a_duration_past_32_bits_uses_version_1_headers():
    frames = flac_mp4.FlacFrames(
        info=flac_mp4.StreamInfo(raw=bytes(34), min_block=65535, max_block=65535, sample_rate=192000,
                                 channels=2, bits_per_sample=24, total_samples=0),
        starts=tuple(range(0, 70000 * 10, 10)), end=700000, block_sizes=(65535,) * 70000)
    moov = flac_mp4._moov(frames, 100)
    for path in [(b"mvhd",), (b"trak", b"tkhd"), (b"trak", b"mdia", b"mdhd")]:
        assert box(moov, b"moov", *path)[0] == 1
    mdhd = box(moov, b"moov", b"trak", b"mdia", b"mdhd")
    assert struct.unpack(">IQ", mdhd[20:32]) == (192000, 65535 * 70000)


# --- against real decoders, where there are some ---------------------------------------------

FFMPEG = shutil.which("ffmpeg")
FFPROBE = shutil.which("ffprobe")
FLAC = shutil.which("flac")
needs_ffmpeg = pytest.mark.skipif(not (FFMPEG and FFPROBE), reason="ffmpeg isn't installed")


def decode(path):
    """Every sample as ffmpeg decodes it, widened to 32 bits so no depth loses anything."""
    return subprocess.run([FFMPEG, "-v", "error", "-i", str(path), "-f", "s32le", "-c:a", "pcm_s32le", "-"],
                          capture_output=True, check=True).stdout


def probe(path):
    out = subprocess.run([FFPROBE, "-v", "error", "-show_entries",
                          "stream=codec_name,channels,duration_ts,duration:format=duration",
                          "-of", "default=nw=1", str(path)], capture_output=True, check=True, text=True).stdout
    return dict(line.split("=", 1) for line in out.splitlines())


def check_decodes_the_same(tmp_path, flac):
    source, repacked = tmp_path / "in.flac", tmp_path / "out.mp4"
    source.write_bytes(flac)
    repacked.write_bytes(flac_to_mp4(flac))
    pcm = decode(source)
    assert pcm and decode(repacked) == pcm
    return probe(repacked)


@needs_ffmpeg
@pytest.mark.parametrize("case", [
    dict(),
    dict(rate=96000, bps=24),
    dict(rate=192000, bps=24, channels=1),
    dict(channels=6, rate=48000),
    dict(blocks=(1152, 4608, 576, 4096, 192, 2000, 4608, 333), variable=True),
    dict(blocks=(4096,) * 8, plant={3: (1000, next_header(3))}),
    dict(id3=id3v2(), trailer=b"TAG" + bytes(125)),
    dict(trailer=bytes(2)),
], ids=["cd", "96k 24-bit", "192k mono", "6 channels", "variable blocks", "false sync", "tags around it",
        "two zeros after"])
def test_the_mp4_decodes_to_the_same_pcm_as_the_flac(tmp_path, case):
    flac, frames = encode(**case)
    info = check_decodes_the_same(tmp_path, flac)
    total = sum(b for _, _, b in frames)
    rate = case.get("rate", 44100)
    assert info["codec_name"] == "flac"
    assert info["channels"] == str(case.get("channels", 2))
    assert abs(float(info["duration"]) - total / rate) < 0.001


@needs_ffmpeg
def test_the_test_encoder_writes_what_it_means_to():
    """ffmpeg reads the encoder's samples back exactly - so what the other tests build is real FLAC."""
    flac, frames = encode(blocks=(256,) * 3, channels=1, seed=7)
    rng = random.Random(7)
    expected = [rng.randrange(-(1 << 15), 1 << 15) for _ in range(256 * 3)]
    out = subprocess.run([FFMPEG, "-v", "error", "-i", "-", "-f", "s16le", "-"], input=flac,
                         capture_output=True, check=True).stdout
    assert list(struct.unpack(f"<{len(expected)}h", out)) == expected


@needs_ffmpeg
@pytest.mark.parametrize("args", [
    ["-ar", "44100", "-ac", "2", "-sample_fmt", "s16"],
    ["-ar", "96000", "-ac", "2", "-sample_fmt", "s32", "-bits_per_raw_sample", "24"],
], ids=["cd", "96k 24-bit"])
def test_ffmpegs_own_flac_repackages_losslessly(tmp_path, args):
    """A real encoder's frames (LPC, Rice coding) rather than verbatim ones."""
    source = tmp_path / "ffmpeg.flac"
    subprocess.run([FFMPEG, "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=4",
                    "-f", "lavfi", "-i", "anoisesrc=d=4:a=0.3", "-filter_complex", "amix=inputs=2",
                    *args, "-c:a", "flac", str(source)], check=True)
    info = check_decodes_the_same(tmp_path, source.read_bytes())
    assert abs(float(info["duration"]) - 4.0) < 0.001


@needs_ffmpeg
@pytest.mark.skipif(not FLAC, reason="the flac tool isn't installed")
def test_libflacs_own_output_repackages_losslessly(tmp_path):
    wav, source = tmp_path / "in.wav", tmp_path / "flac.flac"
    subprocess.run([FFMPEG, "-v", "error", "-f", "lavfi", "-i", "anoisesrc=d=5:a=0.5:c=pink",
                    "-ar", "44100", "-ac", "2", "-sample_fmt", "s16", str(wav)], check=True)
    subprocess.run([FLAC, "-s", "-8", "--padding=4096", "-T", "TITLE=One", "-S", "1s",
                    "-o", str(source), str(wav)], check=True)
    check_decodes_the_same(tmp_path, source.read_bytes())


@pytest.mark.skipif(not FLAC, reason="the flac tool isn't installed")
def test_libflac_accepts_what_the_test_encoder_writes(tmp_path):
    """flac -t checks every frame's CRCs and the STREAMINFO MD5: the fixtures here are valid FLAC,
    the ones this refuses among them - a refusal says a file can't be repackaged with certainty,
    not that it is broken."""
    cases = [dict(), dict(variable=True, blocks=(1152, 4608, 576, 333)), dict(rate=96000, bps=24),
             dict(blocks=(4096,) * 8, plant={3: (1000, next_header(3))})]
    for data in [encode(**case)[0] for case in cases] + [two_readings()[0], copies_of_its_own_header(1000)[0],
                                                          ending_in(0x0000, b"\x00")[0]]:
        path = tmp_path / "t.flac"
        path.write_bytes(data)
        subprocess.run([FLAC, "-s", "-t", str(path)], check=True)
