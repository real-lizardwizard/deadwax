"""
The turntable's windows cut straight from the FLAC, a byte range at a time (src/flac_ranges.py,
2.0.0-player.23) - the pure half. The route's half, through answer_window and a fake Navidrome, is in
test_scrub_window.py.

What it pins:

  - THE EQUALITY: a window cut from the FLAC by ranges is byte for byte the window flac_window.cut_window
    cuts from the plain MP4 of the same file (flac_mp4's own maker), and says the same first sample,
    length and rate - over many (at, seconds): the start, the middle, a frame boundary exactly, the
    last second and the last sample, at and past the end (both PastTheEnd, in the same words), one
    second and sixty, the whole budget and one of three frames (a hi-res song's window, shorter than
    asked). For files of the test encoder - CD, 24/96, mono, variable blocks, one frame, a STREAMINFO
    that doesn't know the length, ID3 tags around it, false syncs planted inside frames, a seek table,
    a cover of megabytes before the seek table and padding after - and, where the `flac` tool is
    installed, real libFLAC files of each kind it can make;
  - the head: read a block at a time, a cover skipped by reading past it - never downloaded - a
    booklet of pictures read past one a read, a seek table's placeholders left out, the file's last
    bytes read for the tags after the audio (a cover in an APEv2 tag never read, the song's end still
    cut), a length not known found at the end, and a head that isn't a FLAC's refused (CannotCut)
    rather than guessed at; at most HEAD_READS reads;
  - finding the frames: a false sync - the next frame's own header, copied into the audio - is never
    taken for a frame; nor is a copy BUILT to pass the CRC-16 (two bytes set) - the read starts before
    the frame found, which has to be one found after another; a seek point that isn't on a frame, or
    names another sample - a later one, or an earlier one as a stale seek table does - is refused,
    never cut from, in the read made from it;
  - bounded: at most WINDOW_READS reads a window, and the bytes read for a window in the middle of a
    long song about its own size - never near the song's - a hidden track after minutes of silence and
    a long song of quiet and loud stretches with no seek table included;
  - flac_mp4._split_frames on a STRETCH: from a frame other than 0, and cut short, answering only the
    frames whose end is certain (a copied header near the end of a read never taken for where a frame
    ends); given the file's last bytes, reading to where the audio ends as the whole file does; called
    as it always was, it answers as it always did (every test in test_flac_mp4.py, unchanged).
"""

import math
import random
import shutil
import struct
import subprocess
import sys
import wave
from functools import lru_cache
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import flac_ranges  # noqa: E402
from src.flac_mp4 import HEADER_MAX, TRAILER_MAX, _crc16, _reach, _split_frames, find_frames, flac_to_mp4  # noqa: E402
from src.flac_window import CannotCut, PastTheEnd, _crc16_after, cut_window  # noqa: E402
from test_flac_mp4 import CD_VARIABLE, encode, frame_header, id3v2, next_header  # noqa: E402

FLAC_TOOL = shutil.which("flac")
needs_flac = pytest.mark.skipif(not FLAC_TOOL, reason="the flac tool isn't installed")

BUDGET = 8 << 20


def reader(data: bytes, log: list | None = None):
    """Reads of `data` as Navidrome answers them, each one written down."""
    def read(offset: int, length: int) -> bytes:
        if log is not None:
            log.append((offset, length))
        return data[offset:offset + length]
    return read


def head_of(flac: bytes, log: list | None = None) -> flac_ranges.Head:
    return flac_ranges.run(flac_ranges.read_head(len(flac)), reader(flac, log))


@lru_cache(maxsize=8)
def mp4_of(flac: bytes) -> bytes:
    return flac_to_mp4(flac)


def from_mp4(flac: bytes, at: float, seconds: float, max_bytes: int = BUDGET):
    """The window cut_window cuts from the plain MP4 of the file - or PastTheEnd's words."""
    mp4 = mp4_of(flac)
    try:
        return cut_window(reader(mp4), len(mp4), at, seconds, max_bytes)
    except PastTheEnd as e:
        return f"past the end: {e}"


def from_flac(flac: bytes, at: float, seconds: float, max_bytes: int = BUDGET, head=None, log=None, points=()):
    """The window cut straight from the file by ranges - or PastTheEnd's words."""
    head = head or head_of(flac)
    try:
        window, _ = flac_ranges.run(flac_ranges.cut(head, at, seconds, max_bytes, points), reader(flac, log))
        return window
    except PastTheEnd as e:
        return f"past the end: {e}"


def same(a, b) -> bool:
    if isinstance(a, str) or isinstance(b, str):
        return a == b
    return (a.data, a.first, a.samples, a.rate, a.song_samples) == (b.data, b.first, b.samples, b.rate, b.song_samples)


def moments(flac: bytes) -> list[float]:
    """Where windows are asked for: the start, the middle, a frame boundary exactly, inside the last
    second and on the last sample, at the end and past it."""
    frames = find_frames(flac)
    rate, total = frames.info.sample_rate, sum(frames.block_sizes)
    #? half a sample over, so int(at * rate) lands on the sample meant whatever the float does
    boundary = sum(frames.block_sizes[:len(frames.block_sizes) // 3])
    return [0.0, total / rate / 2, (boundary + 0.5) / rate, max(0.0, total / rate - 1), (total - 0.5) / rate,
            total / rate, total / rate + 5]


def assert_the_same_windows(flac: bytes, budgets=(BUDGET,)):
    head = head_of(flac)
    frames = find_frames(flac)
    small = 3 * max(frames.sizes())
    checked = 0
    for at in moments(flac):
        for seconds in (1.0, 60.0):
            for max_bytes in (*budgets, small):
                log = []
                mine = from_flac(flac, at, seconds, max_bytes, head=head, log=log)
                assert same(mine, from_mp4(flac, at, seconds, max_bytes)), (at, seconds, max_bytes)
                assert len(log) <= flac_ranges.WINDOW_READS
                checked += 1
    return checked


# ---------------------------------------------------------------- building FLACs to cut from

def metadata(flac: bytes) -> tuple[bytes, list[tuple[int, bytes]], int]:
    """A FLAC's parts: whatever is in front of 'fLaC', its metadata blocks (kind, body), and where its
    audio starts."""
    pos = flac.index(b"fLaC")
    front, pos, blocks = flac[:pos], pos + 4, []
    while True:
        kind, length = flac[pos] & 0x7F, int.from_bytes(flac[pos + 1:pos + 4], "big")
        blocks.append((kind, flac[pos + 4:pos + 4 + length]))
        last = flac[pos] & 0x80
        pos += 4 + length
        if last:
            return front, blocks, pos


def rebuilt(flac: bytes, blocks: list[tuple[int, bytes]]) -> bytes:
    """The FLAC with these metadata blocks in place of its own - its audio, and anything in front of
    it, as they were."""
    front, _, audio = metadata(flac)
    out = bytearray(front + b"fLaC")
    for i, (kind, body) in enumerate(blocks):
        out.append(kind | (0x80 if i == len(blocks) - 1 else 0))
        out += len(body).to_bytes(3, "big") + body
    return bytes(out) + flac[audio:]


def seek_table(flac: bytes, every: int, placeholders: int = 1) -> bytes:
    """A SEEKTABLE body for the file: a point every `every` frames (sample, offset from the first frame,
    samples in it), as libFLAC writes them, then placeholders."""
    frames = find_frames(flac)
    points, sample = [], 0
    for index, (start, block) in enumerate(zip(frames.starts, frames.block_sizes)):
        if index % every == 0:
            points.append(struct.pack(">QQH", sample, start - frames.starts[0], block))
        sample += block
    return b"".join(points) + struct.pack(">QQH", 0xFFFFFFFFFFFFFFFF, 0, 0) * placeholders


def picture(size: int, seed: int = 1) -> bytes:
    """A PICTURE block's body: a front cover of `size` bytes of 'image'."""
    mime, description = b"image/png", b"cover"
    return (struct.pack(">II", 3, len(mime)) + mime + struct.pack(">I", len(description)) + description
            + struct.pack(">IIIII", 1400, 1400, 24, 0, size) + random.Random(seed).randbytes(size))


def with_a_cover(flac: bytes, size: int = 3 << 20, every: int = 4) -> bytes:
    """STREAMINFO, a cover of megabytes, the seek table, the comments, and padding after them."""
    _, blocks, _ = metadata(flac)
    kinds = dict(blocks)
    return rebuilt(flac, [(0, kinds[0]), (6, picture(size)), (3, seek_table(flac, every)), (4, kinds[4]),
                          (1, bytes(8192))])


@lru_cache(maxsize=None)
def long_song(seconds: int = 300, rate: int = 22050, block: int = 4096, every: int | None = None,
              seed: int = 1, silent: float = 0.0, quiet: tuple[tuple[float, float], ...] = ()) -> bytes:
    """
    A long FLAC, made quickly: mono 8-bit frames of verbatim samples (any byte is one), each a run of
    random bytes - eight of them, in turn, so each body's CRC-16 is summed once and carried onto every
    header by the CRC's linearity (flac_window._crc16_after) rather than over megabytes in Python. A
    seek point every `every` frames, when asked for; the first `silent` of the song silence - CONSTANT
    subframes, a few bytes a frame - so its bytes don't follow its samples at all; and silence too in
    each (from, to) of `quiet`, as parts of the song.
    """
    rng = random.Random(seed)
    count = math.ceil(seconds * rate / block)
    blocks = [block] * (count - 1) + [seconds * rate - block * (count - 1)]
    bodies = [b"\x02" + rng.randbytes(block) for _ in range(8)]
    sums = [_crc16(body) for body in bodies]
    frames = []
    for number, size in enumerate(blocks):
        header = frame_header(number, size, rate=rate, channels=1, bps=8, variable=False, rate_style="table")
        if number < silent * count or any(start * count <= number < stop * count for start, stop in quiet):
            #? subframe header 0b0_000000_0: constant, the one sample 0
            body = b"\x00\x00"
            crc = _crc16(header + body)
        elif size == block:
            body, crc = bodies[number % 8], _crc16_after(_crc16(header), block + 1) ^ sums[number % 8]
        else:
            body = b"\x02" + rng.randbytes(size)
            crc = _crc16(header + body)
        frames.append(header + body + crc.to_bytes(2, "big"))
    sizes = [len(frame) for frame in frames]
    streaminfo = struct.pack(">HH", block, block) + min(sizes).to_bytes(3, "big") + max(sizes).to_bytes(3, "big")
    streaminfo += ((rate << 44) | (0 << 41) | (7 << 36) | sum(blocks)).to_bytes(8, "big") + bytes(16)
    flac = b"fLaC" + bytes((0x80, 0, 0, 34)) + streaminfo + b"".join(frames)
    if every:
        flac = rebuilt(flac, [(0, streaminfo), (3, seek_table(flac, every))])
    return flac


# ---------------------------------------------------------------- THE EQUALITY: the test encoder's files

ENCODED = {
    "cd": dict(blocks=(4096,) * 40 + (1000,), seed=11),
    "24/96": dict(rate=96000, bps=24, blocks=(4096,) * 30 + (77,), seed=3),
    "mono": dict(channels=1, blocks=(4096,) * 24 + (17,), seed=5),
    "variable blocks": CD_VARIABLE,
    "one frame": dict(blocks=(1000,), seed=6),
    "length not known": dict(blocks=(4096,) * 30 + (500,), total=0, seed=8),
    "largest frame not known": dict(blocks=(4096,) * 20 + (300,), max_framesize=0, seed=12),
    "tags around it": dict(blocks=(4096,) * 20 + (10,), id3=id3v2(), trailer=b"TAG" + bytes(125), seed=9),
    "false syncs": dict(blocks=(4096,) * 16, plant={3: (1000, next_header(3)), 9: (40, next_header(9))}, seed=10),
}


@pytest.mark.parametrize("name", list(ENCODED))
def test_a_window_from_the_flac_is_the_window_from_its_mp4(name):
    flac, _ = encode(**ENCODED[name])
    assert assert_the_same_windows(flac) == 28


def test_with_a_seek_table_too():
    flac, _ = encode(**ENCODED["cd"])
    _, blocks, _ = metadata(flac)
    kinds = dict(blocks)
    seeking = rebuilt(flac, [(0, kinds[0]), (3, seek_table(flac, 3, placeholders=4)), (4, kinds[4])])
    head = head_of(seeking)
    assert [sample for sample, _ in head.points] == [4096 * n for n in range(0, 41, 3)], "the placeholders left out"
    assert assert_the_same_windows(seeking) == 28


def test_with_a_cover_of_megabytes_before_the_seek_table_and_padding_after():
    flac, _ = encode(**ENCODED["cd"])
    covered = with_a_cover(flac)
    assert assert_the_same_windows(covered) == 28


def test_a_variable_block_stream_with_a_seek_table():
    flac, _ = encode(**ENCODED["variable blocks"])
    _, blocks, _ = metadata(flac)
    kinds = dict(blocks)
    assert assert_the_same_windows(rebuilt(flac, [(0, kinds[0]), (3, seek_table(flac, 5)), (1, bytes(100))])) == 28


def test_a_long_song_mid_song_windows_agree():
    flac = long_song()
    head = head_of(flac)
    for at in (37.3, 150.0, 222.2, 299.5):
        for seconds in (1.0, 40.0, 60.0):
            assert same(from_flac(flac, at, seconds, head=head), from_mp4(flac, at, seconds))


def ape_tag(size: int, seed: int = 1) -> bytes:
    """An APEv2 tag, header and footer, holding one binary item of `size` bytes - a cover, as some taggers
    keep one at the end of a FLAC (flac_mp4._audio_ends reads it)."""
    item = struct.pack("<II", size, 1 << 1) + b"Cover Art (Front)\x00" + random.Random(seed).randbytes(size)
    length = len(item) + 32
    header = b"APETAGEX" + struct.pack("<IIII", 2000, length, 1, 0xA0000000) + bytes(8)
    footer = b"APETAGEX" + struct.pack("<IIII", 2000, length, 1, 0x80000000) + bytes(8)
    return header + item + footer


@pytest.mark.parametrize("name", ["cd", "length not known", "variable blocks"])
def test_a_cover_in_an_apev2_tag_after_the_audio_is_never_read(name):
    """
    A 300 KB cover in an APEv2 tag, and ID3v1 after it, at the end of the file (2.0.0-player.23's review:
    a window reaching the song's end read on into the tag a probe's length at a time until its reads ran
    out, and a probe landing in the tag found no frame - both sent the window to the MP4, which made and
    kept it). The head reads the file's last bytes, which say where the audio can end (Head.end), and no
    window reads past it: the windows - the song's end included - are the MP4 path's, and of the tag only
    its last few hundred bytes are ever read (a probe's worth more where STREAMINFO doesn't know the
    length, read with them).
    """
    flac, _ = encode(**ENCODED[name])
    tagged = flac + ape_tag(300_000) + b"TAG" + bytes(125)
    log = []
    head = head_of(tagged, log)
    assert head.end == len(flac), "the audio ends where the tag begins"
    assert assert_the_same_windows(tagged) == 28
    frames = find_frames(tagged)
    rate, total = frames.info.sample_rate, sum(frames.block_sizes)
    for at in (0.0, total / rate / 2, max(0.0, total / rate - 1), (total - 0.5) / rate):
        for points in ((), head.points):
            from_flac(tagged, at, 60.0, head=head, log=log, points=points)
    inside = sum(max(0, min(offset + length, len(tagged) - TRAILER_MAX) - max(offset, len(flac)))
                 for offset, length in log)
    probe = flac_ranges._probe_length(_reach(head.info))
    assert inside <= (0 if head.info.total_samples else probe), "the tag is never read"


# ---------------------------------------------------------------- THE EQUALITY: libFLAC's own files

def wav(path: Path, seconds: float, rate: int = 44100, channels: int = 2, width: int = 2, seed: int = 1,
        shape: str = "music", silent: float = 0.5) -> Path:
    """A WAV to encode: quiet noise over a tone ("music", which libFLAC's predictors get their teeth
    into), or digital silence for `silent` of it and then loud noise - a song whose bytes don't follow
    its samples at all."""
    rng = random.Random(seed)
    frames = int(seconds * rate)
    if shape == "music":
        tone = [int(8000 * math.sin(2 * math.pi * 220 * n / rate)) for n in range(frames)]
        samples = [value + rng.randrange(-200, 200) for value in tone for _ in range(channels)]
        scale = 256 if width == 3 else 1
        pcm = b"".join((s * scale).to_bytes(width, "little", signed=True) for s in samples)
    else:
        quiet = int(frames * silent)
        pcm = bytes(quiet * channels * width) + rng.randbytes((frames - quiet) * channels * width)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(channels)
        out.setsampwidth(width)
        out.setframerate(rate)
        out.writeframes(pcm)
    return path


def libflac(tmp_path: Path, name: str, *args: str, **sound) -> bytes:
    source = wav(tmp_path / f"{name}.wav", **sound)
    subprocess.run([FLAC_TOOL, "-s", "-f", *args, "-o", str(tmp_path / f"{name}.flac"), str(source)], check=True,
                   stderr=subprocess.DEVNULL)
    return (tmp_path / f"{name}.flac").read_bytes()


@needs_flac
@pytest.mark.parametrize("name, args, sound", [
    ("16/44.1 stereo", ["-5", "-S", "2s"], dict(seconds=8)),
    ("24/96 stereo", ["-5"], dict(seconds=4, rate=96000, width=3)),
    ("mono", ["-8"], dict(seconds=6, channels=1)),
    ("no seek table", ["-5", "--no-seektable"], dict(seconds=8)),
    ("very short", ["-5"], dict(seconds=0.05)),
    ("silence, then noise", ["-5", "--no-seektable"], dict(seconds=12, shape="noise")),
], ids=lambda value: value if isinstance(value, str) else "")
def test_libflacs_own_files_cut_the_same(tmp_path, name, args, sound):
    flac = libflac(tmp_path, "song", *args, **sound)
    assert assert_the_same_windows(flac, budgets=(BUDGET, 600_000)) == 42


@needs_flac
def test_libflacs_file_with_a_cover_before_its_seek_table(tmp_path):
    """libFLAC's own seek table and padding, with a 3 MB cover put in front of them - checked by
    `flac -t` as a valid file - cut the same, the cover never read."""
    flac = libflac(tmp_path, "song", "-5", "-S", "1s", "--padding=8192", seconds=8)
    _, blocks, _ = metadata(flac)
    assert [kind for kind, _ in blocks] == [0, 3, 4, 1], "STREAMINFO, SEEKTABLE, VORBIS_COMMENT, PADDING"
    covered = rebuilt(flac, [blocks[0], (6, picture(3 << 20)), *blocks[1:]])
    (tmp_path / "covered.flac").write_bytes(covered)
    subprocess.run([FLAC_TOOL, "-s", "-t", str(tmp_path / "covered.flac")], check=True)
    log = []
    head = head_of(covered, log)
    assert len(head.points) == 8 and sum(length for _, length in log) <= 2 * flac_ranges.HEAD_CHUNK + TRAILER_MAX
    assert assert_the_same_windows(covered) == 28


@needs_flac
@pytest.mark.parametrize("args", [["-5"], ["-5", "--no-seektable"]], ids=["seek table", "no seek table"])
def test_libflacs_hidden_track_cuts_the_same(tmp_path, args):
    """Three minutes of digital silence and then twenty seconds of noise, libFLAC's own file - mono at
    22.05 kHz, to keep it small (2.0.0-player.23's review: windows starting in the silence before the
    music fell back to the MP4 - two of the eighty across the join with libFLAC's seek table, thirty-four
    without). Every window across the join is the MP4 path's, within its reads."""
    flac = libflac(tmp_path, "song", *args, seconds=200, rate=22050, channels=1, shape="noise", silent=0.9)
    head = head_of(flac)
    for at in [160 + n / 2 for n in range(0, 36)]:
        log = []
        assert same(from_flac(flac, at, 40.0, head=head, log=log), from_mp4(flac, at, 40.0)), at
        assert len(log) <= flac_ranges.WINDOW_READS


# ---------------------------------------------------------------- the head

def test_the_head_is_its_start_and_its_end_for_an_ordinary_file():
    """One read for the metadata, and one of the file's last few hundred bytes - what tags follow the
    audio, said once a version (2.0.0-player.23's review: a cover in an APEv2 tag sent the end of a song
    back to the MP4; until then the head was the one read)."""
    flac, frames = encode(**ENCODED["cd"])
    log = []
    head = head_of(flac, log)
    assert log == [(0, flac_ranges.HEAD_CHUNK), (len(flac) - TRAILER_MAX, TRAILER_MAX)]
    assert (head.first, head.fixed, head.block, head.total) == (frames[0][0], True, 4096, 40 * 4096 + 1000)
    assert head.info == find_frames(flac).info
    assert head.end == len(flac) and head.tail == flac[-TRAILER_MAX:], "no tag: the audio runs to the end"


def test_a_cover_of_megabytes_is_skipped_never_read():
    flac, _ = encode(**ENCODED["cd"])
    covered = with_a_cover(flac, size=5 << 20)
    log = []
    head = head_of(covered, log)
    assert len(log) == 3, "the head, then on from past the cover, then the end of the file"
    assert sum(length for _, length in log) <= 2 * flac_ranges.HEAD_CHUNK + TRAILER_MAX, \
        "not one byte of the cover beyond the first read"
    assert log[1][0] > (5 << 20), "the second read starts past it"
    assert head.first == find_frames(covered).starts[0] and len(head.points) == 11


def test_a_length_not_known_is_found_at_the_end():
    flac, frames = encode(**ENCODED["length not known"])
    log = []
    head = head_of(flac, log)
    assert head.info.total_samples == 0 and head.total == 30 * 4096 + 500
    assert len(log) == 2 and log[1][0] + log[1][1] == len(flac), "one read more, at the end of the file"


def test_the_variable_block_stream_is_told_apart():
    flac, _ = encode(**ENCODED["variable blocks"])
    head = head_of(flac)
    assert head.fixed is False and head.block == 4608


@pytest.mark.parametrize("damage, words", [
    ("noise", "no 'fLaC'"),
    ("an mp4", "no 'fLaC'"),
    ("streaminfo not first", "isn't STREAMINFO"),
    ("streaminfo too short", "isn't STREAMINFO"),
    ("streaminfo without a rate", "STREAMINFO isn't valid"),
    ("type 127", "invalid type 127"),
    ("a block past the end", "runs past the end"),
    ("no audio", "no audio frames"),
    ("no frame where the metadata ends", "no audio frame where"),
    ("a first frame numbered 1", "header isn't valid"),
    ("a broken id3 tag", "ID3v2"),
])
def test_a_head_that_isnt_a_flacs_is_refused(damage, words):
    flac, frames = encode(**ENCODED["cd"])
    front, blocks, audio = metadata(flac)
    kinds = dict(blocks)
    data = {
        "noise": random.Random(2).randbytes(70000),
        "an mp4": flac_to_mp4(flac),
        "streaminfo not first": rebuilt(flac, [(4, kinds[4]), (0, kinds[0])]),
        "streaminfo too short": rebuilt(flac, [(0, kinds[0][:33])]),
        "streaminfo without a rate": rebuilt(flac, [(0, kinds[0][:10] + bytes(3) + kinds[0][13:])]),
        "type 127": rebuilt(flac, [(0, kinds[0]), (127, b"x")]),
        "a block past the end": b"fLaC" + bytes((0, 0, 0, 34)) + kinds[0] + bytes((0x81, 0x0F, 0xFF, 0xFF)) + bytes(100),
        "no audio": flac[:audio],
        "no frame where the metadata ends": flac[:audio] + bytes(100) + flac[audio:],
        "a first frame numbered 1": flac[:audio] + flac[frames[1][0]:],
        "a broken id3 tag": b"ID3\x04\x00\x00\x80\x00\x00\x00" + flac,
    }[damage]
    with pytest.raises(CannotCut, match=words):
        head_of(data)


def covers(flac: bytes, count: int) -> bytes:
    """The FLAC with `count` pictures of 80 KB in front of its audio - a booklet's scans embedded."""
    _, blocks, _ = metadata(flac)
    kinds = dict(blocks)
    return rebuilt(flac, [(0, kinds[0])] + [(6, picture(80_000, seed)) for seed in range(count)] + [(4, kinds[4])])


def test_a_booklet_of_pictures_is_read_past_a_picture_at_a_time():
    """Each picture past the end of the read before it wants a read of its own (to the next block's
    header) - a dozen embedded scans are a dozen reads, once a version, and the windows are as ever
    (2.0.0-player.23's review: HEAD_READS was 6, and six pictures sent every window of the album to
    the MP4)."""
    flac, _ = encode(**ENCODED["cd"])
    booklet = covers(flac, 12)
    log = []
    head = head_of(booklet, log)
    assert len(log) == 14, "the start, one a picture, and the end"
    assert head.first == find_frames(booklet).starts[0]
    assert same(from_flac(booklet, 1.5, 1.0, head=head), from_mp4(booklet, 1.5, 1.0))


def test_a_head_of_more_blocks_than_it_reads_is_refused_not_read_on():
    """Sixty pictures in a row, more than HEAD_READS can read past: the file is laid out as this doesn't
    read - its windows are cut from an MP4 - and the reading stops there, a small fixed number of reads
    in, never one a block however many there are."""
    flac, _ = encode(**ENCODED["cd"])
    log = []
    with pytest.raises(CannotCut, match="more reads"):
        head_of(covers(flac, 60), log)
    assert len(log) == flac_ranges.HEAD_READS < 60


def test_a_seek_table_too_big_to_read_is_skipped():
    flac, _ = encode(**ENCODED["cd"])
    _, blocks, _ = metadata(flac)
    kinds = dict(blocks)
    huge = seek_table(flac, 1) + struct.pack(">QQH", 0xFFFFFFFFFFFFFFFF, 0, 0) * 4000
    assert len(huge) > flac_ranges.SEEKTABLE_MAX
    head = head_of(rebuilt(flac, [(0, kinds[0]), (3, huge)]))
    assert head.points == ()


def test_seek_points_outside_the_song_or_out_of_order_are_left_out():
    flac, _ = encode(**ENCODED["cd"])
    _, blocks, _ = metadata(flac)
    kinds = dict(blocks)
    good = seek_table(flac, 10, placeholders=0)
    table = good + struct.pack(">QQH", 5, 1, 1) + struct.pack(">QQH", 10 ** 9, 0, 0) + struct.pack(">QQH", 50000, 10 ** 9, 0)
    head = head_of(rebuilt(flac, [(0, kinds[0]), (3, table)]))
    assert [sample for sample, _ in head.points] == [0, 40960, 81920, 122880, 163840]


# ---------------------------------------------------------------- finding the frames

def test_a_false_sync_is_never_taken_for_a_frame():
    """A copy of frame 4's own header, CRC-8 and all, planted inside frame 3 - with a STREAMINFO whose
    largest frame lets the copy reach frame 5, so only a checksum can tell: a probe starting just
    before it finds frame 4 where it really is - the copy's frame doesn't sum to zero."""
    flac, frames = encode(blocks=(4096,) * 8, plant={3: (1000, next_header(3))}, max_framesize=40000)
    head = head_of(flac)
    header = frame_header(4, 4096, rate=44100, channels=2, bps=16, variable=False, rate_style="table")
    copy = flac.index(header, frames[3][0] + 10)
    assert copy < frames[4][0], "the plant is a second copy, inside frame 3"
    found = flac_ranges._first_frame(flac[copy - 7:], head.info, True, 4096, head.total, True)
    assert found is not None and copy - 7 + found[0] == frames[4][0] and found[1] == 4 * 4096


def test_a_frame_the_song_cant_hold_is_never_taken_for_one():
    """Whole frames, CRC-16 and all, that don't fit this song - numbered past its end, or of another
    block size in a fixed-block stream - are never taken for its frames (RFC 9639's fields, read
    against this STREAMINFO)."""
    flac, frames = encode(**ENCODED["cd"])
    head = head_of(flac)
    past = encode(blocks=(4096,) * 60, seed=11)[1]
    beyond = past[50][1] + past[51][1] + past[52][1]
    assert flac_ranges._first_frame(beyond, head.info, True, 4096, head.total, False) is None
    other = encode(blocks=(1152,) * 12, seed=11)[1]
    sized = b"".join(frame for _, frame, _ in other[4:10])
    assert flac_ranges._first_frame(sized, head.info, True, 4096, head.total, False) is None
    #? the very same frames, in a song long enough and of their block size, are found
    assert flac_ranges._first_frame(beyond, head.info, True, 4096, 60 * 4096, False)[1] == 50 * 4096
    assert flac_ranges._first_frame(sized, head.info, True, 1152, head.total, False)[1] == 4 * 1152


def test_a_fixed_block_stream_whose_frames_change_size_is_refused():
    flac, frames = encode(blocks=(4096,) * 10 + (2048,) * 20, seed=4)
    info = flac_ranges.run(flac_ranges.read_head(len(flac)), reader(flac)).info
    with pytest.raises(Exception, match="change size"):
        _split_frames(flac[frames[8][0]:], 0, info, 8, to_the_end=False)
    with pytest.raises(CannotCut):
        from_flac(flac, 0.0, 60.0)
    with pytest.raises(CannotCut):
        from_flac(flac, 1.5, 1.0)


def test_a_seek_point_at_a_false_sync_is_refused():
    """A seek point that names a copy of frame 20's own header planted inside frame 19 (and a STREAMINFO
    whose largest frame is big enough for the copy to reach frame 21): the frame read from it doesn't
    sum to zero, so nothing is cut from it."""
    flac, frames = encode(blocks=(4096,) * 30, plant={19: (15000, next_header(19))}, max_framesize=40000, seed=7)
    header = frame_header(20, 4096, rate=44100, channels=2, bps=16, variable=False, rate_style="table")
    copy = flac.index(header, frames[19][0] + 10)
    assert copy < frames[20][0]
    _, blocks, _ = metadata(flac)
    table = b"".join(struct.pack(">QQH", n * 4096, (copy if n == 20 else frames[n][0]) - frames[0][0], 4096)
                     for n in range(0, 30, 10))
    lying = rebuilt(flac, [(0, dict(blocks)[0]), (3, table)])
    #? read from the frame before it, the copy is no frame _split_frames finds (2.0.0-player.23's review;
    #? until then the read began AT the point, and the copy's CRC-16 refused it)
    with pytest.raises(CannotCut, match="isn't a frame of this stream"):
        from_flac(lying, 20.5 * 4096 / 44100, 1.0)


def crafted(at_frame: int, copy_of: int, offset: int, seed: int = 7) -> tuple[bytes, list, int]:
    """
    A file BUILT to fool a reading that takes a frame on its header and CRC-16 (2.0.0-player.23's review):
    frame `copy_of`'s header copied into frame `at_frame`'s audio, and the two bytes before the copy set
    so that frame sums to zero up to the copy as well as to its end - two readings of the file, both
    checking out, which a whole file's reading refuses. Its frames, and where the copy is.
    """
    flac, frames = encode(blocks=(4096,) * 30, plant={at_frame: (offset, lambda headers: headers[copy_of])},
                          max_framesize=40000, seed=seed)
    data = bytearray(flac)
    start, end = frames[at_frame][0], frames[at_frame + 1][0]
    header = frame_header(copy_of, 4096, rate=44100, channels=2, bps=16, variable=False, rate_style="table")
    copy = bytes(data).index(header, start + 10)
    assert copy < end
    data[copy - 2:copy] = _crc16(bytes(data[start:copy - 2])).to_bytes(2, "big")
    data[end - 2:end] = _crc16(bytes(data[start:end - 2])).to_bytes(2, "big")
    return bytes(data), frames, copy


def seeking_to(flac: bytes, frames: list, places: list[tuple[int, int]]) -> bytes:
    """The file with a seek table of these (sample, place in the file)."""
    _, blocks, _ = metadata(flac)
    table = b"".join(struct.pack(">QQH", sample, place - frames[0][0], 4096) for sample, place in places)
    return rebuilt(flac, [(0, dict(blocks)[0]), (3, table)])


@pytest.mark.parametrize("layout", ["in the frame before", "in its own frame"])
def test_a_planted_copy_of_a_header_is_never_a_windows_frame(layout):
    """
    Frame 20's header copied into frame 19 - or into frame 20's own audio - with two bytes set so the
    sums come out (`crafted`): a whole file's reading refuses it, and so a window's must never take the
    copy for frame 20, however it gets there - a seek point naming the copy, or an earlier window's
    frame placed at it. The read starts a frame's reach before the place, the frames are split from the
    frame before, and the copy is found out exactly as in a whole file (or isn't one of them): refused.
    (2.0.0-player.23's review: the read began AT the place, and took the copy on its header and CRC-16.)
    """
    flac, frames, copy = crafted(19, 20, 15000) if layout == "in the frame before" else crafted(20, 20, 6000)
    with pytest.raises(Exception, match="both check out"):
        find_frames(flac)
    lying = seeking_to(flac, frames, [(0, frames[0][0]), (20 * 4096, copy)])
    head, plain = head_of(lying), head_of(flac)
    for at in (20 * 4096 + 50, 20.5 * 4096, 21.2 * 4096):
        with pytest.raises(CannotCut):
            from_flac(lying, at / 44100, 1.0, head=head)
        with pytest.raises(CannotCut):
            from_flac(flac, at / 44100, 1.0, head=plain, points=((20 * 4096, copy),))


def test_a_seek_point_that_lies_never_starts_a_window_on_a_planted_copy():
    """A seek point on frame 21 that says it is frame 20's sample, in the file with frame 20's header
    copied into frame 19: the frame the read's frames are split from is the copy (the real frame 19
    reads two ways, and is passed over), and the window `at` falls in frame 20 would begin on it - but the
    point has to be one of the frames found after it, at the sample they make it, and isn't: refused."""
    flac, frames, copy = crafted(19, 20, 15000)
    lying = seeking_to(flac, frames, [(0, frames[0][0]), (20 * 4096, frames[21][0])])
    with pytest.raises(CannotCut, match="isn't a frame of this stream at the sample said"):
        from_flac(lying, (20 * 4096 + 100) / 44100, 1.0)


def test_the_songs_first_frame_is_taken_as_a_whole_file_takes_it():
    """The first frame, where the metadata ends, is taken on its header - as flac_mp4 takes it from a
    whole file - so a window from it is the MP4 path's even when that frame's own CRC-16 is wrong (only
    the last frame's is summed there): the same bytes, never a window refused that the MP4 path gives."""
    flac, frames = encode(**ENCODED["cd"])
    damaged = bytearray(flac)
    damaged[frames[1][0] - 1] ^= 0xFF
    damaged = bytes(damaged)
    assert _crc16(damaged[frames[0][0]:frames[1][0]]) != 0
    for at in (0.0, 0.05):
        assert same(from_flac(damaged, at, 1.0), from_mp4(damaged, at, 1.0)), at


def test_the_frame_a_read_is_split_from_is_never_kept_for_the_next_window():
    """In the file with frame 20's header copied into frame 19, a window read from frame 21 has its frames
    split from the copy (the real frame 19 reads two ways, and is passed over) - and is right, every frame
    of it found after the copy. But the copy itself is never kept as a place for the song's next window to
    start from: only the frames found after the first are (2.0.0-player.23's review: it was kept, and a
    later window could have begun on it)."""
    flac, frames, copy = crafted(19, 20, 15000)
    original, _ = encode(blocks=(4096,) * 30, plant={19: (15000, lambda headers: headers[20])}, max_framesize=40000,
                         seed=7)
    head = head_of(flac)
    at = 21.5 * 4096 / 44100
    window, found = flac_ranges.run(flac_ranges.cut(head, at, 1.0, BUDGET, ((21 * 4096, frames[21][0]),)), reader(flac))
    assert same(window, from_mp4(original, at, 1.0)), "frames 21 on: the song's, as the file without the plant has them"
    assert found and all(place != copy for _, place in found)


def test_a_seek_point_that_says_another_sample_is_refused_never_cut_from():
    """A seek point at frame 20's very start that says its sample is 100 more than it is: the frames read
    say otherwise, so it is refused (2.0.0-player.23's review: only the point's PLACE had a test, which
    the frames refuse anyway). A window that doesn't start from it is cut, the MP4 path's."""
    flac, frames = encode(**ENCODED["cd"])
    _, blocks, _ = metadata(flac)
    table = bytearray(seek_table(flac, 4, placeholders=0))
    table[5 * 18:5 * 18 + 8] = (20 * 4096 + 100).to_bytes(8, "big")
    lying = rebuilt(flac, [(0, dict(blocks)[0]), (3, bytes(table))])
    for at in (20 * 4096 + 150, 20.5 * 4096, 21.5 * 4096):
        with pytest.raises(CannotCut, match="at the sample said"):
            from_flac(lying, at / 44100, 1.0)
    for at in (0.0, 19.5 * 4096 / 44100):
        assert same(from_flac(lying, at, 1.0), from_mp4(lying, at, 1.0)), at


def stale(early: float = 1.0) -> tuple[bytes, list[tuple[int, int]]]:
    """
    A seek table gone stale (2.0.0-player.23's second review): four minutes of song at 22.05 kHz, loud
    to a minute in, quiet to nearly three, loud again - with points on the real frames at 30 s, 2:00
    and 3:20, each claiming a sample `early` seconds before that frame's. The file, and the points as
    the head reads them: (claimed sample, where the frame starts in the file).
    """
    rate, block = 22050, 4096
    flac = long_song(240, rate, block, quiet=((0.25, 0.7),))
    frames = find_frames(flac)
    numbers = [seconds * rate // block for seconds in (30, 120, 200)]
    table = b"".join(struct.pack(">QQH", n * block - int(early * rate), frames.starts[n] - frames.starts[0], block)
                     for n in numbers)
    _, blocks, _ = metadata(flac)
    return rebuilt(flac, [(0, dict(blocks)[0]), (3, table)]), [
        (n * block - int(early * rate), frames.starts[n] - frames.starts[0]) for n in numbers]


def test_a_seek_point_that_says_an_earlier_sample_is_refused_in_the_read_from_it():
    """
    A stale seek table - each point on a real frame, claiming a sample a second before the frame's: the
    frame the read from a point is split from then starts PAST the window, and the window was looked for
    from there before the point was judged - a ValueError out of _pace for a 32 or 60 s window from the
    point's claimed sample, a 500 through the route where the MP4 path (which reads no seek table) cut
    it (2.0.0-player.23's second review). Refused now, as a point naming a later sample is, and in the
    read made from the point: nothing is read after it (the window then comes from an MP4). Windows
    starting before the first point are the MP4 path's.
    """
    flac, places = stale()
    head = head_of(flac)
    assert [sample for sample, _ in head.points] == [sample for sample, _ in places]
    back = _reach(head.info) + HEADER_MAX
    for sample, place in head.points:
        for later in (0.0, 2.0):
            for seconds in (1.0, 32.0, 60.0):
                log = []
                with pytest.raises(CannotCut, match="at the sample said"):
                    from_flac(flac, (sample + 0.5) / 22050 + later, seconds, head=head, log=log)
                assert log[-1][0] == place - back, ("the read from the point is the last", sample, later, seconds)
    for at in (0.0, 12.0, 27.5):
        for seconds in (1.0, 32.0, 60.0):
            assert same(from_flac(flac, at, seconds, head=head), from_mp4(flac, at, seconds)), (at, seconds)


def test_a_probe_finds_the_first_real_frame_or_says_there_is_none():
    flac, frames = encode(**ENCODED["cd"])
    head = head_of(flac)
    reach = _reach(head.info)
    reads = flac_ranges._Reads(len(flac), 10)
    assert flac_ranges.run(flac_ranges._probe(head, frames[7][0] + 3, reads, reach), reader(flac)) == (frames[8][0], 8 * 4096)
    assert flac_ranges.run(flac_ranges._probe(head, frames[7][0] - 3, reads, reach), reader(flac)) == (frames[7][0], 7 * 4096)
    #? inside the last frame: nothing starts from there to the end
    assert flac_ranges.run(flac_ranges._probe(head, frames[-1][0] + 5, reads, reach), reader(flac)) is None


def test_a_seek_point_that_isnt_on_a_frame_is_refused_never_cut_from():
    flac, frames = encode(**ENCODED["cd"])
    _, blocks, _ = metadata(flac)
    kinds = dict(blocks)
    table = bytearray(seek_table(flac, 4, placeholders=0))
    #? the point for frame 20 moved 100 bytes into it
    table[5 * 18 + 8:5 * 18 + 16] = (frames[20][0] - frames[0][0] + 100).to_bytes(8, "big")
    lying = rebuilt(flac, [(0, kinds[0]), (3, bytes(table))])
    with pytest.raises(CannotCut):
        from_flac(lying, 20.5 * 4096 / 44100, 1.0)
    assert same(from_flac(lying, 0.0, 1.0), from_mp4(lying, 0.0, 1.0)), "a window that doesn't start from it is cut"


def test_frames_that_dont_hold_the_length_streaminfo_says_are_refused():
    flac, frames = encode(blocks=(4096,) * 60, total=4096 * 61)
    with pytest.raises(CannotCut, match="STREAMINFO says 249856"):
        from_flac(flac, 0.5, 60.0)
    #? read from a seek point, not from frame 0: the cut's own check (find_frames refuses the file,
    #? so the table is made from where the encoder put the frames)
    _, blocks, _ = metadata(flac)
    table = b"".join(struct.pack(">QQH", n * 4096, frames[n][0] - frames[0][0], 4096) for n in range(0, 60, 10))
    seeking = rebuilt(flac, [(0, dict(blocks)[0]), (3, table)])
    with pytest.raises(CannotCut, match="where its length says 249856"):
        from_flac(seeking, 45 * 4096 / 44100, 60.0)


# ---------------------------------------------------------------- bounded

def test_a_window_reads_about_its_own_size_never_the_song():
    """Five minutes of song, 6.6 MB, no seek table: each window in the middle reads about its own size -
    the head once, and each window within its WINDOW_READS."""
    flac = long_song()
    log = []
    head = head_of(flac, log)
    assert log == [(0, flac_ranges.HEAD_CHUNK), (len(flac) - TRAILER_MAX, TRAILER_MAX)]
    for at in (40.0, 123.4, 200.0, 250.5):
        log = []
        window = from_flac(flac, at, 40.0, head=head, log=log)
        read = sum(length for _, length in log)
        assert len(log) <= flac_ranges.WINDOW_READS
        assert read <= 1.25 * len(window.data) + 64 * 1024, (at, read, len(window.data))
        assert read < len(flac) / 5


def test_a_song_whose_bytes_dont_follow_its_samples_is_closed_in_on():
    """Half silence (a few bytes a frame), then noise, no seek table: interpolating by the song's length
    puts a moment in the noise far from where it is, and closing in from one side only took more probes
    than a window had (it did, with plain interpolation and with the Illinois rule; now a probe goes
    halfway once the same end has moved twice). Each window still agrees, within its reads and about its
    own size."""
    flac = long_song(seconds=240, silent=0.5)
    head = head_of(flac)
    for at in (121.0, 150.0, 200.0, 230.0):
        log = []
        window = from_flac(flac, at, 40.0, head=head, log=log)
        assert same(window, from_mp4(flac, at, 40.0)), at
        read = sum(length for _, length in log)
        assert len(log) <= flac_ranges.WINDOW_READS
        assert read <= 1.25 * len(window.data) + flac_ranges.PROBES * flac_ranges._probe_length(_reach(head.info)) \
            + 64 * 1024, (at, read, len(window.data))


def test_a_window_running_out_of_silence_into_music_reads_on_far_enough():
    """A song nine tenths silence, with a seek table - a hidden track (2.0.0-player.23's review): a window
    starting in the silence seconds before the music read on at the pace its silent frames had taken,
    each read reaching less far than the one before, until the reads ran out and the window went to the
    MP4, which made and kept it. Read on at the pace of the frames read latest (_pace), each is cut in a
    read or two, the MP4 path's window."""
    flac = long_song(seconds=300, silent=0.9, every=20)
    head = head_of(flac)
    for seconds in (32.0, 40.0):
        for at in range(236, 266):
            log = []
            window = from_flac(flac, float(at), seconds, head=head, log=log)
            assert same(window, from_mp4(flac, float(at), seconds)), (at, seconds)
            assert len(log) <= 3, (at, seconds, log)


@lru_cache(maxsize=None)
def hidden_in_the_middle() -> bytes:
    """Thirty minutes, no seek table: five of sound, twenty of silence, five of sound."""
    return long_song(seconds=1800, quiet=((1 / 6, 5 / 6),))


def test_a_window_after_minutes_of_silence_reads_about_its_own_size():
    """No seek table, and twenty minutes of silence before the last five (2.0.0-player.23's review): four
    probes couldn't close in on the last five minutes, and a window there read five to eight times its
    own size, from far back in the silence. Halving what is left takes most of PROBES, a few kilobytes
    each, and the window reads about its own size again."""
    flac = hidden_in_the_middle()
    head = head_of(flac)
    probes = flac_ranges.PROBES * flac_ranges._probe_length(_reach(head.info))
    for at in (1510.0, 1620.0, 1700.0, 1755.0):
        log = []
        window = from_flac(flac, at, 40.0, head=head, log=log)
        assert same(window, from_mp4(flac, at, 40.0)), at
        read = sum(length for _, length in log)
        assert len(log) <= flac_ranges.WINDOW_READS
        assert read <= 1.25 * len(window.data) + probes + 64 * 1024, (at, read, len(window.data))


def test_a_long_song_whose_loudness_swings_is_closed_in_on():
    """Fifteen minutes of one minute silent, one minute loud, no seek table, and a smaller budget - so
    the read a window may take is a few megabytes, as it is for a long hi-res song under the real one
    (2.0.0-player.23's review: 45 minutes of quiet and loud fell back on one window in eight, four probes
    leaving half the song between them). Each window is cut, the MP4 path's."""
    alternating = tuple((n / 15, (n + 1) / 15) for n in range(0, 15, 2))
    flac = long_song(seconds=900, quiet=alternating)
    head = head_of(flac)
    for at in (130.0, 405.51, 525.04, 545.7, 700.0, 880.0):
        log = []
        window = from_flac(flac, at, 40.0, 1 << 20, head=head, log=log)
        assert same(window, from_mp4(flac, at, 40.0, 1 << 20)), at
        assert len(log) <= flac_ranges.WINDOW_READS


def test_a_window_whose_reads_would_pass_read_limit_is_refused(monkeypatch):
    """read_limit() is what cut() reads within: with no probes allowed, a window at 4:10 would be read from
    the song's first frame - megabytes, past the limit of a small budget - and is refused instead."""
    flac = long_song()
    head = head_of(flac)
    monkeypatch.setattr(flac_ranges, "PROBES", 0)
    with pytest.raises(CannotCut, match="more of the file"):
        from_flac(flac, 250.0, 40.0, 64 << 10, head=head)


def test_a_seek_table_takes_the_probes_away():
    flac = long_song(every=20)
    head = head_of(flac)
    log = []
    window = from_flac(flac, 123.4, 40.0, head=head, log=log)
    assert len(log) <= 2, "from the seek point before it, in one read - or two, when the estimate fell short"
    assert sum(length for _, length in log) <= 1.25 * len(window.data) + 128 * 1024


def test_frames_an_earlier_window_found_are_started_from():
    flac = long_song()
    head = head_of(flac)
    first, found = flac_ranges.run(flac_ranges.cut(head, 100.0, 40.0, BUDGET), reader(flac))
    assert len(found) > 4 and all(a < b for a, b in zip(found, found[1:]))
    log, alone = [], []
    again = from_flac(flac, 132.0, 40.0, head=head, log=log, points=found)
    assert len(log) == 1, "no probe: a frame the last window found is within reach of this one"
    assert same(again, from_mp4(flac, 132.0, 40.0))
    from_flac(flac, 132.0, 40.0, head=head, log=alone)
    assert len(alone) > 1, "without them, a probe first"


def test_more_reads_than_a_window_may_are_refused():
    flac = long_song()
    head = head_of(flac)
    reads = flac_ranges._Reads(len(flac), 2)
    data = flac_ranges.run(reads.read(0, 10), reader(flac))
    assert data == flac[:10]
    flac_ranges.run(reads.read(10, 10), reader(flac))
    with pytest.raises(CannotCut, match="more reads"):
        flac_ranges.run(reads.read(20, 10), reader(flac))
    assert flac_ranges.read_limit(BUDGET, _reach(head.info)) < 3 * BUDGET


def test_more_of_the_file_than_a_window_may_read_is_refused():
    flac = long_song()
    reads = flac_ranges._Reads(len(flac), 10, limit=100)
    flac_ranges.run(reads.read(0, 60), reader(flac))
    with pytest.raises(CannotCut, match="more of the file"):
        flac_ranges.run(reads.read(60, 50), reader(flac))


def test_a_read_that_comes_back_short_is_refused():
    flac, _ = encode(**ENCODED["cd"])
    with pytest.raises(CannotCut, match="came back"):
        flac_ranges.run(flac_ranges.read_head(len(flac)), lambda offset, length: flac[offset:offset + length - 1])


def test_the_points_kept_stay_spread_and_bounded():
    points = tuple((n * 10, n * 100) for n in range(3000))
    kept = flac_ranges.keep_points((), points)
    assert len(kept) <= flac_ranges.POINTS_KEPT and kept[0] == (0, 0) and kept == tuple(sorted(kept))
    assert flac_ranges.keep_points(((5, 5),), ((1, 1), (5, 5))) == ((1, 1), (5, 5))


# ---------------------------------------------------------------- _split_frames on a stretch

def test_a_stretch_answers_only_the_frames_whose_end_is_certain():
    flac, frames = encode(**ENCODED["cd"])
    info = find_frames(flac).info
    reach = _reach(info)
    whole = find_frames(flac)
    start = frames[10][0]
    for cut_at in (start + 3 * reach, start + 3 * reach + 777, len(flac) - 5):
        part = flac[start:cut_at]
        got = _split_frames(part, 0, info, 10, to_the_end=False)
        expected = [s - start for s in whole.starts[10:] if s + reach + HEADER_MAX <= cut_at]
        expected = [s for s in expected if s + start != whole.starts[-1]]
        #? each answered frame has the next frame's start after it
        assert list(got.starts) == expected[:len(got.starts)]
        assert got.starts and got.starts[-1] + reach + HEADER_MAX <= len(part)
        assert got.end == whole.starts[10 + len(got.starts)] - start


def test_a_header_copied_near_the_end_of_a_stretch_is_never_taken_for_where_a_frame_ends():
    """
    Frame 6's header copied into frame 5, and STREAMINFO's largest frame well above the real ones - so a
    stretch can end past the copy and before the real frame 6: the copy then looks like where frame 5
    ends, with a header after it, and nothing in the stretch says otherwise. Only a frame's reach and a
    header of the stretch after frame 5's start make its end certain (2.0.0-player.23's review: a rule
    of "the next header was seen" passed every test, and answered frame 5 cut short at the copy).
    """
    flac, frames = encode(blocks=(4096,) * 12, plant={5: (1000, next_header(5))}, max_framesize=40000, seed=4)
    info = find_frames(flac).info
    reach = _reach(info)
    start = frames[5][0]
    header = frame_header(6, 4096, rate=44100, channels=2, bps=16, variable=False, rate_style="table")
    copy = flac.index(header, start + 10)
    assert copy < frames[6][0] and frames[6][0] - start < reach
    for stop in (copy + 40, frames[6][0] + 40, start + reach + HEADER_MAX - 1):
        assert _split_frames(flac[start:stop], 0, info, 5, to_the_end=False).starts == (), stop
    got = _split_frames(flac[start:start + reach + HEADER_MAX], 0, info, 5, to_the_end=False)
    assert got.starts == (0,) and got.end == frames[6][0] - start, "frame 5, to where frame 6 really starts"


def test_a_stretch_short_of_where_the_last_frame_could_end_is_refused():
    """Given the file's last bytes (`tail`), a stretch to the end that stops before the furthest place the
    last frame could end within its reach - inside the ID3v1 tag after it - is refused rather than summed
    short; one that reaches it reads exactly as the whole file does."""
    flac, frames = encode(**ENCODED["tags around it"])
    whole = find_frames(flac)
    start = frames[19][0]
    tail = (flac[-TRAILER_MAX:], len(flac) - TRAILER_MAX - start)
    with pytest.raises(Exception, match="stops before where the last frame could end"):
        _split_frames(flac[start:len(flac) - 50], 0, whole.info, 19, to_the_end=True, tail=tail)
    got = _split_frames(flac[start:], 0, whole.info, 19, to_the_end=True, tail=tail)
    assert [s + start for s in got.starts] == list(whole.starts[19:]) and got.end + start == whole.end


def test_a_stretch_to_the_end_from_a_later_frame_reads_as_the_whole_file_does():
    flac, frames = encode(**ENCODED["tags around it"])
    whole = find_frames(flac)
    start = frames[15][0]
    got = _split_frames(flac[start:], 0, whole.info, 15, to_the_end=True)
    assert [s + start for s in got.starts] == list(whole.starts[15:]) and got.end + start == whole.end
    with pytest.raises(Exception, match="header isn't valid"):
        _split_frames(flac[start:], 0, whole.info, 14, to_the_end=True)


def test_a_stretch_too_short_for_a_certain_frame_answers_none():
    flac, frames = encode(**ENCODED["cd"])
    info = find_frames(flac).info
    #? frame 6's header is there, but not a frame's reach of the stretch after frame 5's start
    got = _split_frames(flac[frames[5][0]:frames[6][0] + 10], 0, info, 5, to_the_end=False)
    assert got.starts == () and got.end == 0
    #? and no next header at all
    assert _split_frames(flac[frames[5][0]:frames[5][0] + 5000], 0, info, 5, to_the_end=False).starts == ()


def test_the_drivers_answer_alike():
    flac, _ = encode(**ENCODED["cd"])
    steps = flac_ranges.read_head(len(flac))
    done, asked = flac_ranges.advance(steps, None)
    while not done:
        done, asked = flac_ranges.advance(steps, flac[asked[0]:asked[0] + asked[1]])
    assert asked == head_of(flac)
