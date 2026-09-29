"""
FLAC repackaged as an MP4 of the same frames (src/flac_mp4.py) - the fix for Safari's seek bar.

Every FLAC here is made by the small encoder below, which writes VERBATIM subframes: the samples
as they are, which is valid FLAC and lets a test put any bytes it likes inside a frame's audio -
a copy of the next frame's header, the worst false sync there can be. The encoder knows where it
put every frame, so the MP4's tables are checked against the truth rather than against what the
module itself found. No binary fixtures are committed and nothing here needs ffmpeg or flac;
the few tests that use them (decoding both files to PCM and comparing) skip when they're absent.

The fragmented MP4 the gapless player streams (fmp4_layout) is read back box by box the same way,
and a few of its heads are committed as TEXT - tests/fixtures/fmp4_heads.json, which the page's
own parser (ui/test/fmp4.sim.cjs) is held to - and made again here, so the writer and that parser
can't drift apart.
"""

import base64
import hashlib
import json
import os
import random
import re
import shutil
import struct
import subprocess
from pathlib import Path

import pytest

from src import flac_mp4
from src.flac_mp4 import CannotRepackage, NotFlac, Unsupported, flac_to_fmp4, flac_to_mp4, fmp4_layout

# --- a FLAC encoder, verbatim subframes (or constant ones) -----------------------------------

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
           rate_style="table", seed=1, plant=None, total=None, id3=b"", trailer=b"", max_framesize=None,
           constant=False):
    """A FLAC file, and the frames in it as (offset, bytes, block size).

    `plant` maps a frame index to (byte offset into its first channel's samples, bytes) - or to a
    function of the list of every frame's header that returns them, to copy a real header in.
    `max_framesize` is what STREAMINFO says the largest frame is: the truth unless it is given,
    and 0 for "not known", as an encoder writing to a pipe leaves it. `constant` writes each
    channel of each frame as one CONSTANT subframe instead - a single sample standing for the whole
    block, which is valid FLAC a dozen bytes a frame, for files whose audio nobody looks at.
    """
    assert not (constant and plant), "a constant subframe has no samples to plant anything in"
    rng = random.Random(seed)
    width = bps // 8
    headers, number = [], 0
    for block in blocks:
        headers.append(frame_header(number, block, rate=rate, channels=channels, bps=bps,
                                    variable=variable, rate_style=rate_style))
        number += block if variable else 1
    frames, pcm = [], bytearray()
    for index, (block, header) in enumerate(zip(blocks, headers)):
        body = bytearray()
        if constant:
            values = []
            for _ in range(channels):
                #? subframe header 0b0_000000_0: constant, no wasted bits
                value = rng.randrange(-(1 << (bps - 1)), 1 << (bps - 1))
                body.append(0x00)
                body += value.to_bytes(width, "big", signed=True)
                values.append([value] * block)
        else:
            samples = [[rng.randrange(-(1 << (bps - 1)), 1 << (bps - 1)) for _ in range(block)]
                       for _ in range(channels)]
            for channel in samples:
                #? subframe header 0b0_000001_0: verbatim, no wasted bits
                body.append(0x02)
                body += b"".join(s.to_bytes(width, "big", signed=True) for s in channel)
            if plant and index in plant:
                at, what = plant[index]
                what = what(headers) if callable(what) else what
                body[1 + at:1 + at + len(what)] = what
            #? what STREAMINFO's MD5 is taken over: interleaved, little-endian - read back from the
            #? planted body so the checksum matches what the file really holds
            values = [[int.from_bytes(body[at:at + width], "big", signed=True)
                       for at in range(1 + c * (1 + block * width), (c + 1) * (1 + block * width), width)]
                      for c in range(channels)]
        frame = header + bytes(body)
        frame += struct.pack(">H", crc16(frame))
        frames.append(frame)
        for i in range(block):
            for c in range(channels):
                pcm += values[c][i].to_bytes(width, "little", signed=True)
    sizes = [len(f) for f in frames]
    min_block = min(blocks[:-1]) if len(blocks) > 1 else blocks[0]
    streaminfo = struct.pack(">HH", min_block, max(blocks))
    largest = max(sizes) if max_framesize is None else max_framesize
    streaminfo += min(sizes).to_bytes(3, "big") + largest.to_bytes(3, "big")
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


#? One of each shape the muxer handles differently, for the goldens below and the fragmented ones
GOLDEN_CASES = {
    "fixed blocks": dict(blocks=(4096,) * 30 + (1234,)),
    "variable blocks": dict(blocks=(1152, 4608, 576, 4096, 192, 2000, 16, 4608, 4608, 4608, 333), variable=True),
    "96 kHz 24-bit": dict(rate=96000, bps=24, blocks=(4096,) * 30 + (77,)),
    "6 channels": dict(rate=48000, channels=6, blocks=(1152,) * 50 + (300,)),
    "id3v2 in front": dict(id3=id3v2(), blocks=(4096,) * 12 + (1000,), seed=3),
    "id3v1 and ape after": dict(blocks=(4096,) * 12 + (1000,), seed=4, trailer=(
        b"APETAGEX" + struct.pack("<IIII8x", 2000, 64, 0, 0xA0000000) + bytes(32)
        + b"APETAGEX" + struct.pack("<IIII8x", 2000, 64, 0, 0x80000000) + b"TAG" + bytes(125))),
}

#? sha256 of flac_to_mp4() for each, recorded from the muxer as 1.1.0-player.5 shipped it. The
#? player's cache names an MP4 by FORMAT_VERSION and serves ranges of it across a re-make after an
#? eviction, so an MP4 whose bytes changed under the same FORMAT_VERSION would be spliced into one
#? made before: a change here needs FORMAT_VERSION (player_cache.py) bumped, never just new hashes.
MP4_GOLDENS = {
    "fixed blocks": "88f3b18de7da93e68ca8aa7d0c7c98ab8765070097028a59713af911b13f2faa",
    "variable blocks": "577295f264d68515fe8bc7772059b2fad3028815d7f9f85f9ad0f8beb3e27378",
    "96 kHz 24-bit": "bad4dc51343376fc8cac8e4ac38ce22adfd0af350cc4470ad879d14baeff9de3",
    "6 channels": "34cafbd463e1d08ab4615340f63403bf88cd41c64b63bc389e60444dc0dad9b3",
    "id3v2 in front": "2099b3efa268a5a331ce206cffe72afeefab250ed5f71a3ffad659d8139fb14b",
    "id3v1 and ape after": "2eab9b641060cd2b388f4cf35d5d8c93fbd9606c7ef37bdf0bf1a009b276508c",
}


@pytest.mark.parametrize("name", list(MP4_GOLDENS))
def test_the_mp4_is_byte_for_byte_what_it_was(name):
    flac, _ = encode(**GOLDEN_CASES[name])
    assert hashlib.sha256(flac_to_mp4(flac)).hexdigest() == MP4_GOLDENS[name]


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


def header_check(head, fix_crc=True):
    """What `_frame_header` makes of `head` (with its CRC-8 made right unless told otherwise)."""
    data = bytes(head) + (bytes([crc8(bytes(head))]) if fix_crc else b"") + bytes(20)
    return flac_mp4._frame_header(data, 0, CD)


def test_a_good_header_is_read():
    assert header_check(GOOD) == (5, 4096, 6)
    assert header_check([0xFF, 0xF8, 0x79, 0x88, 5, 0x0F, 0xFF]) == (5, 4096, 8)   # a 16-bit tail
    #? which number it ought to carry is for the caller to say
    assert header_check(GOOD[:4] + [6]) == (6, 4096, 6)


@pytest.mark.parametrize("number", [0, 127, 128, 2047, 2048, (1 << 16) - 1, 1 << 16, (1 << 21) - 1, 1 << 21,
                                    (1 << 26) - 1, 1 << 26, (1 << 31) - 1, 1 << 31, (1 << 36) - 1])
def test_a_number_of_every_length_is_read(number):
    """Frame numbers take up to six bytes to write and sample numbers seven."""
    assert header_check(GOOD[:4] + list(coded(number))) == (number, 4096, 5 + len(coded(number)))


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
    ([0xFF, 0xF8, 0xC9, 0x88, 0xC0, 0x85], "number 5, written the long way"),
    ([0xFF, 0xF8, 0xC9, 0x88, 0xE0, 0x9F, 0xBF], "number 2047, written the long way"),
    ([0xFF, 0xF8, 0xC9, 0x88, 0x85], "a number starting with a continuation byte"),
    ([0xFF, 0xF8, 0xC9, 0x88, 0xC2, 0x05], "a number whose second byte isn't a continuation"),
    ([0xFF, 0xF8, 0xC9, 0x88, 0xFF, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80], "0xFF, which starts no number"),
])
def test_a_header_wrong_in_any_one_field_is_not_a_frame(head, why):
    assert header_check(head) is None, why


def test_a_header_with_a_bad_crc_is_not_a_frame():
    good = bytes(GOOD) + bytes([crc8(bytes(GOOD))])
    assert header_check(list(good), fix_crc=False) == (5, 4096, 6)
    assert header_check(list(good[:-1]) + [good[-1] ^ 1], fix_crc=False) is None


@pytest.mark.parametrize("head", [[0xFF, 0xF8, 0x79, 0x88, 5, 0x0F], [0xFF, 0xF8, 0xC9, 0x88, 0xE1, 0x80]],
                         ids=["in its block size", "in its number"])
def test_a_header_cut_off_by_the_end_of_the_file_is_not_a_frame(head):
    assert flac_mp4._frame_header(bytes(head), 0, CD) is None


def test_a_first_frame_that_isnt_number_0_is_refused():
    flac, frames = encode()
    at = frames[0][0]
    header = bytearray(flac[at:at + 6])
    header[4] = 1
    header[5] = crc8(bytes(header[:5]))
    with pytest.raises(Unsupported, match="first audio frame"):
        flac_to_mp4(flac[:at] + bytes(header) + flac[at + 6:])


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


def test_two_false_headers_in_a_row_are_found_out_by_the_frame_before_them():
    """Copies of frames 4 AND 5 inside frame 3 are both taken for frames; the real frame 4's header
    then carries a number given two frames back, and frame 3 checks out to it and not to the copy."""
    flac, frames = encode(blocks=(4096,) * 8, plant={3: (1000, lambda h: h[4] + bytes(40) + h[5])})
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def chained_copies(copies=2, solve=None):
    """A valid FLAC with copies of the headers of frames 2, 3 ... (as many as `copies`) inside frame
    1, one after another, each just after two bytes that can be set. `solve` sets a pair so that a
    checksum comes to zero at a copy: "first" makes frame 1 check out ending at the first copy, and
    "between" makes the stretch from the first copy to the second check out as a frame. Returns the
    file, its frames, and where the copies are."""
    blocks, at, gap = (4096,) * 6 + (1000,), 2000, 40

    def build(fixes):
        run = lambda h: b"".join(bytes(gap if n else 0) + fix + h[2 + n] for n, fix in enumerate(fixes))
        return encode(blocks=blocks, seed=7, plant={1: (at, run)})

    fixes = [bytes(2)] * copies
    flac, frames = build(fixes)
    start = frames[1][0]
    places = [start + 6 + 1 + at + 2 + n * (2 + gap + 6) for n in range(copies)]
    if solve == "first":
        fixes[0] = struct.pack(">H", crc16(flac[start:places[0] - 2]))
    elif solve == "between":
        fixes[1] = struct.pack(">H", crc16(flac[places[0]:places[1] - 2]))
    flac, frames = build(fixes)
    for n, place in enumerate(places):
        assert flac[place:place + 6] == frames[2 + n][1][:6]
    return flac, frames, places


@pytest.mark.parametrize("copies", [2, 3])
def test_a_chain_of_header_copies_is_found_out_by_the_frame_before_it(copies):
    flac, frames, _ = chained_copies(copies)
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_a_chain_whose_copies_check_out_as_a_frame_is_still_found_out():
    """The second copy used to be all the next check looked for, so a copy of frame 2's header and
    then of frame 3's, the stretch between them made to check out, was kept: the real frame 2's
    header carried a number no longer looked for and was passed over. It is looked for now, and
    frame 1 doesn't check out to the first copy."""
    flac, frames, (first, second) = chained_copies(solve="between")
    assert crc16(flac[first:second]) == 0 and crc16(flac[frames[1][0]:first]) != 0
    assert_same_frames(flac_to_mp4(flac), flac, frames)


@pytest.mark.parametrize("copies", [2, 3])
def test_a_chain_where_the_frame_before_checks_out_to_the_first_copy_is_refused(copies):
    """Frame 1 checks out ending at the first copy AND at the real frame 2: two readings. The first
    used to be kept, splitting a valid FLAC in the wrong place."""
    flac, frames, (first, *_) = chained_copies(copies, solve="first")
    assert crc16(flac[frames[1][0]:first]) == 0
    with pytest.raises(Unsupported, match="number 2, and both check out"):
        flac_to_mp4(flac)


def test_a_header_numbered_further_back_than_a_frame_can_reach_is_passed_over_unsummed(monkeypatch):
    """A copy of frame 2's header inside frame 5: frame 1 would have to run on into frame 5 for it
    to be the real one, far past STREAMINFO's largest frame - so it isn't, and nothing is summed to
    say so. A real file carries a header like it about once in 2^34 bytes."""
    flac, frames = encode(blocks=(4096,) * 8, plant={5: (100, lambda h: h[2])})
    summed, crc16_of = [], flac_mp4._crc16
    monkeypatch.setattr(flac_mp4, "_crc16", lambda data, crc=0: summed.append(len(data)) or crc16_of(data, crc))
    assert_same_frames(flac_to_mp4(flac), flac, frames)
    assert sum(summed) == len(frames[-1][1])


def test_a_header_numbered_back_but_within_reach_is_checked_and_passed_over(monkeypatch):
    """With small frames and room for large ones, the copy of frame 2's header in frame 4 could be
    the real one as far as sizes go, so frames 1 to 3 are summed: they check out where they were
    taken to end, and frame 1 doesn't to the copy."""
    flac, frames = encode(blocks=(256,) * 8, max_framesize=20000, plant={4: (100, lambda h: h[2])})
    summed, crc16_of = [], flac_mp4._crc16
    monkeypatch.setattr(flac_mp4, "_crc16", lambda data, crc=0: summed.append(len(data)) or crc16_of(data, crc))
    assert_same_frames(flac_to_mp4(flac), flac, frames)
    assert sum(summed) > sum(len(f) for _, f, _ in frames[1:4])


def test_a_frame_too_large_with_a_copy_of_the_next_header_halfway_is_refused_not_split_there():
    """STREAMINFO says frames reach 12000 bytes; frame 2 is 16 KB with a copy of frame 3's header
    halfway. Each half fits the reach, so the copy is taken - and the real frame 3's header, a
    frame's reach and more from frame 2's start, carries the number just given. That one is checked
    whatever the distance: frame 2 checks out to it and not to the copy, which makes frame 2 larger
    than STREAMINFO allows."""
    blocks = (1152, 1152, 4096, 100, 1152)
    flac, frames = encode(blocks=blocks, variable=True, max_framesize=12000, plant={2: (7000, lambda h: h[3])})
    assert frames[3][0] - frames[2][0] > 12000
    with pytest.raises(Unsupported, match="larger than any frame of this stream can be"):
        flac_to_mp4(flac)


def test_a_copy_of_the_next_header_in_a_frame_whose_checksum_is_wrong_is_refused():
    """Frame 1 checks out neither at the copy nor at the real frame 2: the file isn't what it says."""
    flac, frames = encode(blocks=(4096,) * 6, plant={1: (1000, next_header(1))})
    footer = frames[2][0] - 1
    damaged = flac[:footer] + bytes([flac[footer] ^ 0x5A]) + flac[footer + 1:]
    with pytest.raises(Unsupported, match="number 2, and neither checks out"):
        flac_to_mp4(damaged)


@pytest.mark.parametrize("where", [1, 3, 4], ids=["the second frame", "a middle frame", "the last frame"])
def test_a_frame_larger_than_streaminfo_says_any_can_be_is_refused(where):
    """A frame past STREAMINFO's largest means STREAMINFO is wrong, and the reach that decides what
    can be a frame with it - so nothing it decided is trusted."""
    blocks = [1152] * 5
    blocks[where] = 4096
    flac, frames = encode(blocks=tuple(blocks), variable=True, max_framesize=len(encode(blocks=(1152,))[1][0][1]) + 20)
    with pytest.raises(Unsupported, match="larger than any frame of this stream can be"):
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


def test_copies_frame_after_frame_are_summed_in_one_pass(monkeypatch):
    """Copies of frame 1's header in frame 1, then of frame 2's in frame 2: the second lot's sums
    start from frame 1's, which had come back to zero at frame 2 - so frame 1 isn't summed twice."""
    flac, frames = encode(blocks=(4096,) * 5, plant={1: (0, lambda h: h[1] * 500), 2: (0, lambda h: h[2] * 500)})
    summed = counting_sums(monkeypatch)
    assert_same_frames(flac_to_mp4(flac), flac, frames)
    assert sum(summed) <= len(frames[0][1]) + len(frames[1][1]) + 7 + 6 * 499 + len(frames[-1][1])


def test_a_large_tag_after_the_audio_is_left_out_without_summing_it(monkeypatch):
    """An APEv2 tag with a cover in it runs to hundreds of KB. Ending the last frame after it would
    make that frame larger than any can be, so the tag is never summed."""
    items = bytes(1 << 20)
    flac, frames = encode(trailer=items + b"APETAGEX" + struct.pack("<IIII8x", 2000, len(items) + 32, 1, 0))
    summed = counting_sums(monkeypatch)
    assert_same_frames(flac_to_mp4(flac), flac, frames)
    assert sum(summed) == len(frames[-1][1])


def test_a_tag_that_checks_out_as_audio_beyond_a_frames_reach_is_left_out():
    """The last frame checks out both before an ID3v1 tag and after it, but it is already as large
    as STREAMINFO's largest, so running on through the tag would make it larger than any frame can
    be: there is only one reading, and the tag is left out."""
    body = b"TAG" + bytes(123)
    flac, frames = encode(blocks=(4096,) * 5, trailer=body + struct.pack(">H", crc16(body)))
    assert crc16(flac[frames[-1][0]:]) == 0
    assert_same_frames(flac_to_mp4(flac), flac, frames)


def test_checksumming_is_bounded_and_refused_past_the_bound(monkeypatch):
    """A file as it should be sums its last frame and nothing else, which the bound covers many
    times over."""
    flac, frames = encode()
    assert flac_mp4.CHECKSUM_BUDGET > 100 * len(frames[-1][1])
    monkeypatch.setattr(flac_mp4, "CHECKSUM_BUDGET", len(frames[-1][1]))
    assert_same_frames(flac_to_mp4(flac), flac, frames)
    monkeypatch.setattr(flac_mp4, "CHECKSUM_BUDGET", len(frames[-1][1]) - 1)
    with pytest.raises(Unsupported, match="checksumming"):
        flac_to_mp4(flac)


def counting_sums(monkeypatch):
    summed, crc16_of = [], flac_mp4._crc16
    monkeypatch.setattr(flac_mp4, "_crc16", lambda data, crc=0: summed.append(len(data)) or crc16_of(data, crc))
    return summed


def test_megabytes_after_the_audio_are_refused_without_summing_a_byte(monkeypatch):
    """The last frame's checksum used to run to the end of the file and the one before it again:
    64 MiB appended took nine seconds to refuse, and every other Safari song waited on it. An end
    further from the last frame's start than any frame can reach is no end at all."""
    flac, _ = encode(blocks=(4096, 1000))
    summed = counting_sums(monkeypatch)
    with pytest.raises(Unsupported, match="larger than any frame of this stream can be"):
        flac_to_mp4(flac + b"\x01" * (16 << 20))
    assert sum(summed) == 0


def test_a_stream_claiming_huge_frames_is_summed_no_further_than_the_bound(monkeypatch):
    """STREAMINFO can claim frames of up to 16 MiB, which puts megabytes appended within reach:
    then the bound - the same whatever the file's size - is what stops the summing. Sync codes
    through the tail make the sum go stretch by stretch rather than ask for it all at once."""
    flac, _ = encode(blocks=(4096, 1000), max_framesize=(1 << 24) - 1)
    tail = (b"\x01" * 65534 + b"\xff\xf8") * 160
    summed = counting_sums(monkeypatch)
    with pytest.raises(Unsupported, match="far too much checksumming"):
        flac_to_mp4(flac + tail)
    assert flac_mp4.CHECKSUM_BUDGET - 65536 < sum(summed) <= flac_mp4.CHECKSUM_BUDGET


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


@pytest.mark.parametrize("what, largest_known, refusal", [
    ("its first three frames again", True, "larger than any frame"),
    ("its first three frames again", False, "larger than any frame"),
    ("a frame of another stream", True, "larger than any frame"),
    ("a frame of another stream", False, "more frames"),
    ("a short frame of another stream", True, "more frames"),
    ("its last frame again", True, "number 4, and both check out"),
], ids=["3 frames", "3 frames, largest unknown", "another's", "another's, largest unknown", "another's short one",
        "its last again"])
def test_whole_frames_after_the_last_are_refused(what, largest_known, refusal):
    """Each checks out on its own, so the last frame's checksum comes to zero at the end of the
    file as well, and the MP4's last sample would have held them all. What catches them: the last
    sample coming out larger than any frame of the stream can be - STREAMINFO's largest frame when
    it gives one, a frame of verbatim samples when not - or else the checksum coming to zero at a
    sync code before the end."""
    flac, frames = encode(blocks=(4096,) * 4 + (100,), max_framesize=None if largest_known else 0)
    extra = {
        "its first three frames again": lambda: b"".join(f for _, f, _ in frames[:3]),
        "a frame of another stream": lambda: encode(rate=48000, seed=5)[1][1][1],
        "a short frame of another stream": lambda: encode(rate=48000, seed=5, blocks=(4096, 100))[1][1][1],
        "its last frame again": lambda: frames[-1][1],
    }[what]()
    with pytest.raises(Unsupported, match=refusal):
        flac_to_mp4(flac + extra)


def other_strategy(frame, header_length):
    """`frame` with its blocking-strategy bit flipped and both checksums made right again: a whole
    frame that sums to zero, beginning with the OTHER sync code."""
    body = bytearray(frame[:-2])
    body[1] ^= 0x01
    body[header_length - 1] = crc8(bytes(body[:header_length - 1]))
    body = bytes(body)
    flipped = body + struct.pack(">H", crc16(body))
    assert crc16(flipped) == 0 and flipped[:2] == (b"\xff\xf8" if frame[1] == 0xF9 else b"\xff\xf9")
    return flipped


@pytest.mark.parametrize("variable", [False, True], ids=["0xFFF9 after a fixed stream", "0xFFF8 after a variable one"])
@pytest.mark.parametrize("which, largest_known, refusal", [
    ("its first frame", True, "larger than any frame"),
    ("its first frame", False, "more frames"),
    ("its last frame", True, "more frames"),
], ids=["first, largest known", "first, largest unknown", "last"])
def test_a_whole_frame_of_the_other_blocking_strategy_after_the_last_is_refused(variable, which, largest_known, refusal):
    """Only the stream's own sync code used to be looked for in the last frame, so a frame written
    with the other one went into the last sample every time: a 60 s flac -8 file with its first
    frame appended that way stopped in AVFoundation at 57.8 s as an MP4."""
    blocks = (4096,) * 4 + (100,)
    flac, frames = encode(blocks=blocks, variable=variable, max_framesize=None if largest_known else 0)
    index = 0 if which == "its first frame" else len(blocks) - 1
    number = sum(blocks[:index]) if variable else index
    header = frame_header(number, blocks[index], rate=44100, channels=2, bps=16, variable=variable, rate_style="table")
    assert frames[index][1].startswith(header)
    with pytest.raises(Unsupported, match=refusal):
        flac_to_mp4(flac + other_strategy(frames[index][1], len(header)))


@pytest.mark.parametrize("args, expected", [
    (dict(channels=2, bits_per_sample=16, max_block=4096), 16 + 2 * 3 + (33 * 4096 + 7) // 8 + 2),
    (dict(channels=1, bits_per_sample=8, max_block=16), 16 + 2 + 16 + 2),
    (dict(channels=6, bits_per_sample=24, max_block=4608), 16 + 6 * 4 + 6 * 24 * 4608 // 8 + 2),
    (dict(channels=8, bits_per_sample=32, max_block=65535), 16 + 8 * 5 + 8 * 32 * 65535 // 8 + 2),
    (dict(channels=2, bits_per_sample=16, max_block=4096, max_framesize=12345), 12345),
], ids=["cd", "8-bit mono", "5.1 24-bit", "the largest FLAC allows", "streaminfo's"])
def test_a_frames_reach_is_streaminfos_largest_or_else_its_samples_stored_verbatim(args, expected):
    info = flac_mp4.StreamInfo(raw=bytes(34), min_block=16, sample_rate=44100, total_samples=0, **args)
    assert flac_mp4._reach(info) == expected


@pytest.mark.parametrize("case", [
    dict(), dict(rate=96000, bps=24, blocks=(4608,) * 3 + (7,)), dict(channels=1, bps=8, rate=8000, blocks=(16,) * 300),
    dict(channels=8, bps=24, rate=48000, blocks=(1152,) * 4), dict(bps=32, blocks=(4096,) * 3 + (5,)),
    dict(blocks=(1152, 4608, 576, 16, 4608), variable=True),
], ids=["cd", "96k 24-bit", "8-bit mono", "8 channels", "32-bit", "variable blocks"])
def test_with_no_largest_frame_given_every_verbatim_frame_is_within_reach(case):
    """An encoder writing to a pipe leaves STREAMINFO's largest frame 0. The test encoder writes
    nothing but verbatim frames - the largest a frame is ever written - so all of these must
    still wrap, their last frame summed and nothing else refused."""
    flac, frames = encode(**case, max_framesize=0)
    assert_same_frames(flac_to_mp4(flac), flac, frames)


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


# --- the fragmented MP4, for one stream across songs ------------------------------------------

def full(body):
    """(version, flags, the rest) of a FullBox's body."""
    return body[0], int.from_bytes(body[1:4], "big"), body[4:]


def children(data, *path):
    return [k for k, _, _ in boxes(data, *_body(data, *path))]


def read_fmp4(data):
    """
    Everything an MSE player takes from a fragmented file, read box by box and checked as it goes:
    ftyp, moov and sidx, then moof + mdat pairs to the end - each fragment's samples found the way
    a player finds them, from its moof (default-base-is-moof) through its trun.
    """
    top = boxes(data)
    kinds = [k for k, _, _ in top]
    assert kinds[:3] == [b"ftyp", b"moov", b"sidx"], kinds[:4]
    assert len(kinds) % 2 == 1 and kinds[3:] == [b"moof", b"mdat"] * ((len(kinds) - 3) // 2), kinds
    ftyp = box(data, b"ftyp")
    stbl = (b"moov", b"trak", b"mdia", b"minf", b"stbl")

    version, flags, mvhd = full(box(data, b"moov", b"mvhd"))
    assert (version, flags) == (0, 0)
    creation, modification, movie_scale, movie_duration = struct.unpack(">IIII", mvhd[:16])
    version, tkhd_flags, tkhd = full(box(data, b"moov", b"trak", b"tkhd"))
    assert version == 0
    track, _, track_duration = struct.unpack(">III", tkhd[8:20])
    layer, group, volume = struct.unpack(">HHH", tkhd[28:34])
    version, flags, mdhd = full(box(data, b"moov", b"trak", b"mdia", b"mdhd"))
    assert (version, flags) == (0, 0)
    _, _, timescale, duration, language, _ = struct.unpack(">IIIIHH", mdhd)
    stsd = box(data, *stbl, b"stsd")
    assert struct.unpack(">I", stsd[4:8])[0] == 1
    entry = stsd[8:]
    entry_size, entry_kind = struct.unpack(">I4s", entry[:8])
    assert entry_kind == b"fLaC" and entry_size == len(entry)
    channels, sample_size, _, _, entry_rate = struct.unpack(">HHHHI", entry[24:36])
    (dfla_kind, dfla_start, dfla_end), = boxes(entry, 36)
    tables = {kind: box(data, *stbl, kind) for kind in (b"stts", b"stsc", b"stsz", b"stco")}
    trex = full(box(data, b"moov", b"mvex", b"trex"))

    (_, sidx_start, sidx_end) = top[2]
    version, flags, sidx = full(data[sidx_start:sidx_end])
    assert (version, flags) == (0, 0)
    reference_id, sidx_scale, earliest, first_offset, _, count = struct.unpack(">IIIIHH", sidx[:20])
    references = [struct.unpack(">III", sidx[20 + 12 * i:32 + 12 * i]) for i in range(count)]
    assert len(sidx) == 20 + 12 * count

    fragments, expected_t0 = [], 0
    for (_, moof_start, moof_end), (_, mdat_start, mdat_end) in zip(top[3::2], top[4::2]):
        base = moof_start - 8
        assert children(data[base:moof_end], b"moof") == [b"mfhd", b"traf"]
        moof = data[base:moof_end]
        assert children(moof, b"moof", b"traf") == [b"tfhd", b"tfdt", b"trun"]
        _, _, mfhd = full(box(moof, b"moof", b"mfhd"))
        _, tfhd_flags, tfhd = full(box(moof, b"moof", b"traf", b"tfhd"))
        fields, at = {"track": struct.unpack(">I", tfhd[:4])[0]}, 4
        for bit, name, width in [(0x01, "base offset", 8), (0x02, "description", 4), (0x08, "duration", 4),
                                 (0x10, "size", 4), (0x20, "flags", 4)]:
            if tfhd_flags & bit:
                fields[name] = int.from_bytes(tfhd[at:at + width], "big")
                at += width
        assert at == len(tfhd)
        tfdt_version, _, tfdt = full(box(moof, b"moof", b"traf", b"tfdt"))
        t0 = struct.unpack(">Q" if tfdt_version == 1 else ">I", tfdt)[0]
        trun_version, trun_flags, trun = full(box(moof, b"moof", b"traf", b"trun"))
        samples_in, = struct.unpack(">I", trun[:4])
        at, data_offset = 4, None
        if trun_flags & 0x01:
            data_offset, = struct.unpack(">i", trun[at:at + 4])
            at += 4
        if trun_flags & 0x04:
            at += 4
        durations, sizes = [], []
        for _ in range(samples_in):
            durations.append(struct.unpack(">I", trun[at:at + 4])[0] if trun_flags & 0x100 else fields["duration"])
            at += 4 if trun_flags & 0x100 else 0
            sizes.append(struct.unpack(">I", trun[at:at + 4])[0] if trun_flags & 0x200 else fields["size"])
            at += 4 if trun_flags & 0x200 else 0
            at += 4 * bool(trun_flags & 0x400) + 4 * bool(trun_flags & 0x800)
        assert at == len(trun)
        #? the samples are where the moof says: counted from the moof's first byte, and exactly
        #? filling the mdat after it
        first = base + data_offset
        assert first == mdat_start and first + sum(sizes) == mdat_end
        samples, offset = [], first
        for size in sizes:
            samples.append(data[offset:offset + size])
            offset += size
        assert t0 == expected_t0, "each fragment starts where the one before ended"
        expected_t0 += sum(durations)
        fragments.append({
            "start": base, "end": mdat_end, "sequence": struct.unpack(">I", mfhd)[0], "tfhd_flags": tfhd_flags,
            "tfhd": fields, "tfdt_version": tfdt_version, "t0": t0, "trun_version": trun_version,
            "trun_flags": trun_flags, "durations": durations, "sizes": sizes, "samples": samples,
            "units": sum(durations), "moof_size": moof_end - base,
        })

    assert [f["start"] for f in fragments][:1] == [sidx_end], "the first fragment straight after the index"
    return {
        "ftyp": (ftyp[:4], struct.unpack(">I", ftyp[4:8])[0], [ftyp[i:i + 4] for i in range(8, len(ftyp), 4)]),
        "init_end": top[1][2], "index_end": sidx_end,
        "moov": children(data, b"moov"), "trak": children(data, b"moov", b"trak"),
        "mdia": children(data, b"moov", b"trak", b"mdia"), "minf": children(data, b"moov", b"trak", b"mdia", b"minf"),
        "stbl": children(data, *stbl),
        "mvhd": (creation, modification, movie_scale, movie_duration, struct.unpack(">I", mvhd[92:96])[0]),
        "tkhd": (tkhd_flags, track, track_duration, layer, group, volume),
        "timescale": timescale, "duration": duration, "language": language,
        "hdlr": box(data, b"moov", b"trak", b"mdia", b"hdlr"), "stsd": stsd,
        "channels": channels, "sample_size": sample_size, "entry_rate": entry_rate,
        "dfla": (dfla_kind, entry[dfla_start:dfla_end]),
        "tables": {kind: full(body)[2] for kind, body in tables.items()}, "trex": trex,
        "sidx": {"reference_id": reference_id, "timescale": sidx_scale, "earliest": earliest,
                 "first_offset": first_offset, "references": references},
        "fragments": fragments,
    }


def assert_same_fragmented_frames(fmp4, flac, frames):
    """Every frame once, in order, each one sample timed by its block size - and the FLAC's own bytes."""
    got = read_fmp4(fmp4)
    assert [s for f in got["fragments"] for s in f["samples"]] == [f for _, f, _ in frames]
    assert [d for f in got["fragments"] for d in f["durations"]] == [b for _, _, b in frames]
    first, last = frames[0][0], frames[-1][0] + len(frames[-1][1])
    assert b"".join(fmp4[f["start"] + f["moof_size"] + 8:f["end"]] for f in got["fragments"]) == flac[first:last]
    return got


CD_FIXED = dict(blocks=(4096,) * 30 + (1234,))
#? fragment by fragment: ten 4608s (one duration), then a mix (13 frames), then 4096s and a short one
CD_VARIABLE = dict(blocks=(4608,) * 10 + (1152, 4608, 576, 4096, 192, 2000) + (4608,) * 7 + (4096,) * 5 + (333,),
                   variable=True)


def test_an_fmp4_is_the_labs_layout_box_for_box():
    """
    What ffmpeg wrote for the phone lab (-movflags frag_keyframe+empty_moov+default_base_moof, one
    second a fragment), which played seamlessly on James's iPhone: box for box, field for field,
    less its udta, plus the sidx the page reads as the index.
    """
    flac, frames = encode(**CD_FIXED)
    fmp4 = flac_to_fmp4(flac)
    got = assert_same_fragmented_frames(fmp4, flac, frames)

    assert got["ftyp"] == (b"iso5", 512, [b"iso5", b"iso6", b"mp41"])
    assert got["moov"] == [b"mvhd", b"trak", b"mvex"], "no mehd, no udta"
    assert got["trak"] == [b"tkhd", b"mdia"], "no edit list"
    assert got["mdia"] == [b"mdhd", b"hdlr", b"minf"]
    assert got["minf"] == [b"smhd", b"dinf", b"stbl"]
    assert got["stbl"] == [b"stsd", b"stts", b"stsc", b"stsz", b"stco"]
    assert got["mvhd"] == (0, 0, 44100, 0, 2), "timescale the sample rate, duration 0, next track 2"
    assert got["tkhd"] == (3, 1, 0, 0, 1, 0x0100), "enabled and in the movie, track 1, alternate group 1"
    assert (got["timescale"], got["duration"], got["language"]) == (44100, 0, flac_mp4._LANGUAGE_UND)
    assert got["hdlr"][8:12] == b"soun" and got["hdlr"].endswith(b"SoundHandler\x00")
    assert box(fmp4, b"moov", b"trak", b"mdia", b"minf", b"dinf", b"dref") == (
        bytes(4) + struct.pack(">I", 1) + struct.pack(">I4sI", 12, b"url ", 1))
    assert got["tables"] == {b"stts": bytes(4), b"stsc": bytes(4), b"stsz": bytes(8), b"stco": bytes(4)}
    assert got["trex"] == (0, 0, struct.pack(">IIIII", 1, 1, 0, 0, 0))
    #? the sample description is the plain MP4's, byte for byte - one song's format is the other's
    assert got["stsd"] == box(flac_to_mp4(flac), b"moov", b"trak", b"mdia", b"minf", b"stbl", b"stsd")
    assert (got["channels"], got["sample_size"], got["entry_rate"]) == (2, 16, 44100 << 16)

    assert [len(f["samples"]) for f in got["fragments"]] == [11, 11, 9], "whole frames, about a second each"
    for number, fragment in enumerate(got["fragments"], start=1):
        assert fragment["sequence"] == number
        assert fragment["tfhd_flags"] == 0x020038
        assert fragment["tfhd"] == {"track": 1, "duration": fragment["durations"][0],
                                    "size": fragment["sizes"][0], "flags": 0x02000000}
        assert (fragment["tfdt_version"], fragment["trun_version"]) == (1, 0)
    assert [f["trun_flags"] for f in got["fragments"]] == [0x201, 0x201, 0x301], "durations only for the short last"


def test_the_sidx_indexes_every_fragment():
    flac, frames = encode(**CD_FIXED)
    fmp4 = flac_to_fmp4(flac)
    got = read_fmp4(fmp4)
    sidx = got["sidx"]

    assert (sidx["reference_id"], sidx["timescale"], sidx["earliest"], sidx["first_offset"]) == (1, 44100, 0, 0)
    assert [(size, units) for size, units, _ in sidx["references"]] == [
        (f["end"] - f["start"], f["units"]) for f in got["fragments"]]
    assert all(size < 1 << 31 for size, _, _ in sidx["references"]), "reference_type 0: media, not another index"
    assert {sap for _, _, sap in sidx["references"]} == {0x90000000}, "each starts with a sync sample"
    assert sum(size for size, _, _ in sidx["references"]) == len(fmp4) - got["index_end"]
    assert sum(units for _, units, _ in sidx["references"]) == sum(b for _, _, b in frames)


def test_the_layout_is_the_head_and_each_fragments_header_then_its_frames():
    """What the cache writes: the head, then per fragment its moof and mdat header and a slice of the
    FLAC it already holds - never a copy of the audio."""
    flac, frames = encode(**CD_VARIABLE)
    head, fragments = fmp4_layout(flac)
    fmp4 = flac_to_fmp4(flac)
    got = read_fmp4(fmp4)

    assert fmp4.startswith(head) and len(head) == got["index_end"]
    assert len(fragments) == len(got["fragments"])
    starts = iter(frames)
    for (header, start, end), fragment in zip(fragments, got["fragments"]):
        assert header == fmp4[fragment["start"]:fragment["start"] + fragment["moof_size"] + 8]
        assert header[-8:] == struct.pack(">I4s", 8 + end - start, b"mdat")
        held = [next(starts) for _ in fragment["samples"]]
        assert (start, end) == (held[0][0], held[-1][0] + len(held[-1][1])), "whole frames, straight from the FLAC"


def test_trun_lists_durations_only_in_a_fragment_whose_frames_differ():
    """0x201 where every frame has the fragment's default duration, 0x301 where any differs - in the
    middle of a variable-block stream too, not only at a short last frame."""
    flac, frames = encode(**CD_VARIABLE)
    got = assert_same_fragmented_frames(flac_to_fmp4(flac), flac, frames)

    assert [len(f["samples"]) for f in got["fragments"]] == [10, 13, 6]
    assert [f["trun_flags"] for f in got["fragments"]] == [0x201, 0x301, 0x301]
    assert got["fragments"][1]["durations"] == [1152, 4608, 576, 4096, 192, 2000] + [4608] * 7
    assert [f["tfhd"]["duration"] for f in got["fragments"]] == [4608, 1152, 4096], "the first frame's"


def test_every_sample_is_a_sync_sample():
    """A FLAC frame depends on no other: tfhd flags them all so (sample_depends_on 2, not non-sync),
    as ffmpeg does, and no trun overrides it."""
    flac, _ = encode(**CD_VARIABLE)
    for fragment in read_fmp4(flac_to_fmp4(flac))["fragments"]:
        assert fragment["tfhd"]["flags"] == 0x02000000
        assert not fragment["trun_flags"] & (0x004 | 0x400)


def test_each_fragment_starts_where_the_one_before_ended():
    flac, frames = encode(**CD_VARIABLE)
    got = read_fmp4(flac_to_fmp4(flac))
    assert [f["t0"] for f in got["fragments"]] == [0, 46080, 46080 + 44880]
    assert got["fragments"][-1]["t0"] + got["fragments"][-1]["units"] == sum(b for _, _, b in frames)


@pytest.mark.parametrize("rate, channels, bps, per_fragment", [(96000, 2, 24, 24), (48000, 6, 16, 42)],
                         ids=["96 kHz 24-bit", "6 channels"])
def test_hi_res_and_surround_are_still_written(rate, channels, bps, per_fragment):
    """The page decides what it streams (48 kHz, stereo, 16 or 24 bits); deadwax writes any FLAC it
    can split, with the real rate as the timescale and the sample entry's clamped as isoflac says."""
    block = 4096 if rate == 96000 else 1152
    flac, frames = encode(rate=rate, channels=channels, bps=bps, blocks=(block,) * (per_fragment + 5) + (77,))
    got = assert_same_fragmented_frames(flac_to_fmp4(flac), flac, frames)
    assert (got["timescale"], got["mvhd"][2], got["sidx"]["timescale"]) == (rate, rate, rate)
    assert (got["channels"], got["sample_size"]) == (channels, bps)
    assert got["entry_rate"] == min(rate, 48000) << 16
    assert [len(f["samples"]) for f in got["fragments"]] == [per_fragment, 6]


def test_tags_around_the_audio_are_left_out_of_the_fmp4():
    flac, frames = encode(**GOLDEN_CASES["id3v1 and ape after"])
    assert_same_fragmented_frames(flac_to_fmp4(flac), flac, frames)
    untagged, _ = encode(blocks=(4096,) * 12 + (1000,), seed=3)
    tagged, frames = encode(**GOLDEN_CASES["id3v2 in front"])
    assert flac_to_fmp4(tagged) == flac_to_fmp4(untagged)
    assert_same_fragmented_frames(flac_to_fmp4(tagged), tagged, frames)


def test_the_fmp4_is_the_same_every_time():
    flac, _ = encode(**CD_VARIABLE)
    assert flac_to_fmp4(flac) == flac_to_fmp4(bytearray(flac)) == flac_to_fmp4(flac)
    assert fmp4_layout(flac) == fmp4_layout(flac)


@pytest.mark.parametrize("make, refusal", [
    (lambda: encode()[0][:-700], Unsupported),
    (lambda: encode(blocks=(4096, 4096, 1024, 4096, 100))[0], Unsupported),
    (lambda: b"RIFF" + bytes(40), NotFlac),
    (lambda: encode()[0] + bytes(16), Unsupported),
], ids=["cut short", "fixed blocks changing size", "not flac", "zeros after the audio"])
def test_what_the_mp4_refuses_the_fmp4_refuses(make, refusal):
    data = make()
    with pytest.raises(refusal) as mp4:
        flac_to_mp4(data)
    with pytest.raises(refusal) as fmp4:
        fmp4_layout(data)
    assert str(fmp4.value) == str(mp4.value)


def test_a_song_with_more_fragments_than_an_index_can_list_is_refused(monkeypatch):
    """sidx counts its references in 16 bits - 18 hours at a second a fragment. Not built at that
    length here: the bound is lowered to what a short file reaches."""
    assert flac_mp4.SIDX_MAX_REFERENCES == 0xFFFF
    flac, _ = encode(**CD_FIXED)
    monkeypatch.setattr(flac_mp4, "SIDX_MAX_REFERENCES", 3)
    assert len(fmp4_layout(flac)[1]) == 3
    monkeypatch.setattr(flac_mp4, "SIDX_MAX_REFERENCES", 2)
    with pytest.raises(Unsupported, match="too long for a fragment index"):
        fmp4_layout(flac)


#? sha256 of flac_to_fmp4() for GOLDEN_CASES, recorded once the structure matched the lab's file.
#? player_cache.py names a fragmented MP4 by FMP4_FORMAT_VERSION, and the page's If-Range carries
#? on across a re-make after an eviction: a change here (CHUNK_SECONDS included) needs that bumped.
FMP4_GOLDENS = {
    "fixed blocks": "d9151d16fa9d315caf67e5ebbb931c920146620930f684568efe486a154f3cff",
    "variable blocks": "2daae0d520d68c9f417a7bf3ef095635538d56b560ba8292d36f8661533a2be8",
    "96 kHz 24-bit": "ad40646058a969e26e665068db724f711ed15c3ab693f1149e922701b7062499",
    "6 channels": "9b94926b693da5e247395918f16d61385c72818951e1d90a8f8f221ae0d36485",
    "id3v2 in front": "30f8dcef98d67cb359c232a7874d9dc81669ae320d968fe826b5a52aeadcef1b",
    "id3v1 and ape after": "c3125860acd635beaf380058cd1d06f41c806fbd1f92f1d7096f2b0d1f8e5e4f",
}


@pytest.mark.parametrize("name", list(FMP4_GOLDENS))
def test_the_fmp4_is_byte_for_byte_what_it_was(name):
    flac, _ = encode(**GOLDEN_CASES[name])
    assert hashlib.sha256(flac_to_fmp4(flac)).hexdigest() == FMP4_GOLDENS[name]


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


def check_decodes_the_same(tmp_path, flac, wrap=flac_to_mp4):
    source, repacked = tmp_path / "in.flac", tmp_path / "out.mp4"
    source.write_bytes(flac)
    repacked.write_bytes(wrap(flac))
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
@pytest.mark.parametrize("case", [
    dict(),
    dict(rate=96000, bps=24, blocks=(4096,) * 30 + (77,)),
    dict(channels=6, rate=48000, blocks=(1152,) * 50 + (300,)),
    CD_VARIABLE,
    dict(blocks=(4096,) * 8, plant={3: (1000, next_header(3))}),
    dict(id3=id3v2(), trailer=b"TAG" + bytes(125)),
    dict(trailer=bytes(2)),
], ids=["cd", "96k 24-bit", "6 channels", "variable blocks", "false sync", "tags around it", "two zeros after"])
def test_the_fmp4_decodes_to_the_same_pcm_as_the_flac(tmp_path, case):
    """ffmpeg reads a fragmented MP4 as a player does - init, index, fragments - to the very samples."""
    flac, frames = encode(**case)
    info = check_decodes_the_same(tmp_path, flac, wrap=flac_to_fmp4)
    assert info["codec_name"] == "flac"
    assert info["channels"] == str(case.get("channels", 2))
    assert abs(float(info["duration"]) - sum(b for _, _, b in frames) / case.get("rate", 44100)) < 0.001


@needs_ffmpeg
def test_ffmpegs_own_flac_repackages_losslessly_as_an_fmp4(tmp_path):
    """A real encoder's frames (LPC, Rice coding) in fragments."""
    source = tmp_path / "ffmpeg.flac"
    subprocess.run([FFMPEG, "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=4",
                    "-f", "lavfi", "-i", "anoisesrc=d=4:a=0.3", "-filter_complex", "amix=inputs=2",
                    "-ar", "44100", "-ac", "2", "-sample_fmt", "s16", "-c:a", "flac", str(source)], check=True)
    info = check_decodes_the_same(tmp_path, source.read_bytes(), wrap=flac_to_fmp4)
    assert abs(float(info["duration"]) - 4.0) < 0.001


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


@needs_ffmpeg
@pytest.mark.skipif(not FLAC, reason="the flac tool isn't installed")
def test_libflacs_output_with_its_first_frame_appended_the_other_way_is_refused(tmp_path):
    """The review's case, from a real encoder: flac -8's own file, then its frame 0 again with the
    blocking-strategy bit flipped. It wraps as it is; with the frame appended the last sample would
    run well past the largest frame STREAMINFO says the file has."""
    wav, source = tmp_path / "in.wav", tmp_path / "flac.flac"
    subprocess.run([FFMPEG, "-v", "error", "-f", "lavfi", "-i", "anoisesrc=d=5:a=0.5:c=pink",
                    "-ar", "44100", "-ac", "2", "-sample_fmt", "s16", str(wav)], check=True)
    subprocess.run([FLAC, "-s", "-8", "-o", str(source), str(wav)], check=True)
    data = source.read_bytes()
    frames = flac_mp4.find_frames(data)
    flac_to_mp4(data)
    first = data[frames.starts[0]:frames.starts[1]]
    header_length = flac_mp4._frame_header(data, frames.starts[0], frames.info)[2]
    with pytest.raises(Unsupported, match="larger than any frame|more frames"):
        flac_to_mp4(data + other_strategy(first, header_length))


@needs_ffmpeg
def test_a_chain_found_out_decodes_to_the_same_pcm(tmp_path):
    flac, _, _ = chained_copies(solve="between")
    check_decodes_the_same(tmp_path, flac)


@pytest.mark.skipif(not FLAC, reason="the flac tool isn't installed")
def test_libflac_accepts_what_the_test_encoder_writes(tmp_path):
    """flac -t checks every frame's CRCs and the STREAMINFO MD5: the fixtures here are valid FLAC,
    the ones this refuses among them - a refusal says a file can't be repackaged with certainty,
    not that it is broken."""
    cases = [dict(), dict(variable=True, blocks=(1152, 4608, 576, 333)), dict(rate=96000, bps=24),
             dict(blocks=(4096,) * 8, plant={3: (1000, next_header(3))})]
    crafted = [two_readings()[0], copies_of_its_own_header(1000)[0], ending_in(0x0000, b"\x00")[0],
               chained_copies(3)[0], chained_copies(solve="first")[0], chained_copies(solve="between")[0]]
    for data in [encode(**case)[0] for case in cases] + crafted:
        path = tmp_path / "t.flac"
        path.write_bytes(data)
        subprocess.run([FLAC, "-s", "-t", str(path)], check=True)


@needs_ffmpeg
def test_constant_frames_are_real_flac_too(tmp_path):
    """The heads committed for the page's parser are made of constant subframes, to stay small:
    ffmpeg decodes each to its one value, held for the block, in the FLAC and in the fragments."""
    flac, frames = encode(**HEAD_CASES["cd, fixed blocks, a short last frame"])
    check_decodes_the_same(tmp_path, flac, wrap=flac_to_fmp4)
    pcm = decode(tmp_path / "in.flac")
    assert len(pcm) == sum(b for _, _, b in frames) * 2 * 4
    assert pcm[:8] * 4096 == pcm[:8 * 4096], "the first frame is one value a channel, all through"


# --- the heads the page's parser is held to --------------------------------------------------

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "fmp4_heads.json"
#? what the page fetches first of a song (HEAD_FETCH_BYTES in ui/src/lib/fmp4.ts): the
#? init segment, the index and the first fragments, in one range
HEAD_FETCH_BYTES = 262144

#? Constant subframes keep these a few kilobytes: the parser reads boxes, never the audio.
HEAD_CASES = {
    "cd, fixed blocks, a short last frame": dict(blocks=(4096,) * 30 + (1234,), constant=True, seed=11),
    "48 kHz 24-bit": dict(rate=48000, bps=24, blocks=(4608,) * 25 + (100,), constant=True, seed=12),
    "cd, variable blocks": dict(CD_VARIABLE, constant=True, seed=13),
    "an id3v2 tag in front": dict(id3=id3v2(), blocks=(4096,) * 20 + (777,), constant=True, seed=14),
}


def head_fixture() -> str:
    """tests/fixtures/fmp4_heads.json as the writer makes it now, and as the page must read it."""
    heads = []
    for name, case in HEAD_CASES.items():
        flac, frames = encode(**case)
        fmp4 = flac_to_fmp4(flac)
        got = assert_same_fragmented_frames(fmp4, flac, frames)
        heads.append({
            "name": name,
            "total": len(fmp4),
            "expect": {
                "initEnd": got["init_end"],
                "indexEnd": got["index_end"],
                "timescale": got["timescale"],
                "units": sum(b for _, _, b in frames),
                "format": {"sampleRate": case.get("rate", 44100), "channels": case.get("channels", 2),
                           "bitsPerSample": case.get("bps", 16)},
                #? [start, end) in the file, and the units before it and in it
                "fragments": [[f["start"], f["end"], f["t0"], f["units"]] for f in got["fragments"]],
            },
            "b64": base64.b64encode(fmp4[:HEAD_FETCH_BYTES]).decode("ascii"),
        })
    text = json.dumps({"heads": heads}, indent=2)
    #? a list of numbers on one line, so a fragment reads as one
    return re.sub(r"\[\s*(-?\d+(?:,\s*-?\d+)*)\s*\]", lambda m: "[" + re.sub(r"\s+", " ", m.group(1)) + "]", text) + "\n"


def test_the_committed_heads_are_what_the_writer_makes():
    """
    The page's fmp4 parser is tested against these (ui/test/fmp4.sim.cjs), so a change to the writer
    that this doesn't see would leave the two disagreeing with both suites green. Run with
    REGENERATE_FMP4_HEADS=1 to write the file afresh - after checking the parser still reads it.
    """
    made = head_fixture()
    if os.environ.get("REGENERATE_FMP4_HEADS") == "1":
        FIXTURE.parent.mkdir(exist_ok=True)
        FIXTURE.write_text(made, encoding="ascii")
    assert FIXTURE.read_text(encoding="ascii") == made, "the writer changed: REGENERATE_FMP4_HEADS=1 writes it again"
    assert made.isascii()


def test_the_committed_heads_say_what_they_hold():
    """Each head, read back from its bytes: whole files (they are small), with the fragments the
    index lists, and a trun with durations in the fragments whose frames differ."""
    heads = json.loads(FIXTURE.read_text(encoding="ascii"))["heads"]
    assert [head["name"] for head in heads] == list(HEAD_CASES)
    for head in heads:
        data = base64.b64decode(head["b64"])
        assert len(data) == min(head["total"], HEAD_FETCH_BYTES)
        expect = head["expect"]
        got = read_fmp4(data)
        assert (got["init_end"], got["index_end"], got["timescale"]) == (
            expect["initEnd"], expect["indexEnd"], expect["timescale"])
        assert [size for size, _, _ in got["sidx"]["references"]] == [end - start for start, end, _, _ in expect["fragments"]]
        assert expect["fragments"][0][0] == expect["indexEnd"] and expect["fragments"][-1][1] == head["total"]
        assert sum(units for _, _, _, units in expect["fragments"]) == expect["units"]
    flags = {head["name"]: [f["trun_flags"] for f in read_fmp4(base64.b64decode(head["b64"]))["fragments"]]
             for head in heads}
    assert flags["cd, variable blocks"] == [0x201, 0x301, 0x301]
    assert flags["cd, fixed blocks, a short last frame"] == [0x201, 0x201, 0x301]
